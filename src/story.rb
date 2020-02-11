# frozen_string_literals: true

require 'pry'
require 'set'
require 'yaml'

require_relative 'boolean_superposition'
require_relative 'minmax'

class Story
  attr_reader :data, :analysis, :backlinks, :possible_flags, :possible_vars

  def initialize(filename)
    @data = YAML.load_file(filename)
  end

  def analyze
    @analysis = {}
    @backlinks = {}
    @possible_flags = {}
    @possible_vars = {}
    results = traverse('intro')

    coverage = analyze_coverage(results)
    zero_visits = coverage.select { |_, num| num == 0 }.keys

    zero_visit_reasons = zero_visits.each_with_object({}) do |node, result|
      sources = @backlinks[node].to_a
      result[node] = sources.map { |source| possible_vars[source] }
    end

    @analysis[:never_hit] = zero_visit_reasons

    results
  end

  def traverse(id, vars_orig = {}, crumbs_orig = [])
    id = id.to_s if id.is_a?(Symbol)

    raise TypeError, "#{id}: expected id to be String" unless id.is_a?(String)

    raise TypeError, "#{id}: expected vars to be Hash" unless vars_orig.is_a?(Hash)

    raise TypeError, "#{id}: expected crumbs to be Array" unless crumbs_orig.is_a?(Array)

    vars = vars_orig.dup
    crumbs = crumbs_orig.dup

    crumbs.push(id)

    # Duplicate the node/vars at this level.
    node = data[id]

    raise TypeError, "#{id}: expected node to be Hash" unless node.is_a?(Hash)

    result_data = {
      'crumbs' => crumbs,
      'vars' => vars
    }

    # First check if the node was already visited.
    if crumbs_orig.include?(id)
      warn_cycle(id)
      return [result_data]
    end


    if node['flags'].is_a?(Hash)
      node['flags'].each do |(flagname, value)|
        unless value == true || value == false
          raise TypeError, "#{id}: flag #{flagname} must be true or false (was #{value})"
        end

        if vars[flagname] == true && flagname.start_with?('first_')
          warn_first_again(id, flagname, crumbs, vars)
        end

        vars[flagname] = value
      end
    end

    if node['values'].is_a?(Hash)
      node['values'].each do |(varname, rules)|
        op = ''
        num = 0

        case rules
        when String
          rules.strip!
          tokens = rules.split(/\b/).map(&:strip)
          case tokens[0]
          when '=', '-', '+'
            op = tokens[0]
            num = tokens[1].to_i
          when Integer
            op = '='
            num = tokens[0].to_i
          else
            raise TypeError, "#{id}: don't know how to parse '#{rules}'"
          end
        when Integer
          op = '='
          num = rules
        when Hash
          op = rules['op'].to_s
          num = rules['value'].to_i
        else
          raise TypeError, "#{id}: expected #{rules} to be String, Integer, or Hash"
        end

        case op
        when '='
          vars[varname] = num
        when '-'
          vars[varname] ||= 0
          vars[varname] -= num
          if vars[varname] < 0
            warn_decrement(id, varname, crumbs, vars)
            vars[varname] = 0
          end
        when '+'
          vars[varname] ||= 0
          vars[varname] += num
        else
          raise TypeError, "#{id}: invalid operator '#{op}' provided"
        end
      end
    end

    # Update possible values of all vars at this point in traversal.
    vars.each do |(varname, varvalue)|
      @possible_vars[id] ||= {}

      # TODO: this will fail if a var is a flag in one node and a number in
      #       another, should handle that more error condition more gracefully
      case varvalue
      when FalseClass, TrueClass
        @possible_vars[id][varname] ||= BooleanSuperposition.new(varvalue)
      when Integer
        @possible_vars[id][varname] ||= MinMax.new(varvalue, varvalue)
      end

      @possible_vars[id][varname] += varvalue
    end

    link_ids = Set.new((node['links'] || {}).keys)
    result_data['links'] = link_ids
    result_data['locked_links'] = Set.new

    link_results = []
    if node['links'].is_a?(Hash)
      node['links'].each do |(link, conditions)|
        @backlinks[link] ||= Set.new
        @backlinks[link].add(id)

        can_visit = true
        if conditions.is_a?(Hash)
          flag_conditions = conditions['flags']
          value_conditions = conditions['values']
          if flag_conditions.is_a?(Hash)
            flag_conditions.each do |(flagname, value)|
              can_visit &= ((vars[flagname] || false) == value)
            end
          end

          if value_conditions.is_a?(Hash)
            value_conditions.each do |varname, rules|
              op = ''
              num = 0

              case rules
              when String
                rules.strip!
                tokens = rules.split(/\b/).map(&:strip)
                case tokens[0]
                when '=', '==', '<', '>'
                  op = tokens[0]
                  num = tokens[1].to_i
                when Integer
                  op = '='
                  num = tokens[0].to_i
                else
                  raise TypeError, "#{id}: don't know how to parse '#{rules}'"
                end
              when Integer
                op = '=='
                num = rules.to_i
              when Hash
                op = rules['op'].to_s
                num = rules['value'].to_i
              else
                raise TypeError,
                      "#{id}: expected #{rules} to be String, Integer, or Hash"
              end

              case op
              when '=', '=='
                can_visit &= ((vars[varname] || 0) == num)
              when '<'
                can_visit &= ((vars[varname] || 0) < num)
              when '>'
                can_visit &= ((vars[varname] || 0) > num)
              else
                raise TypeError, "#{id}: invalid comparison operator '#{op}' provided"
              end
            end
          end
        end

        if !data.key?(link)
          warn_missing_node(id, link)
        elsif can_visit
          link_results.concat(traverse(link, vars, crumbs))
        else
          result_data['links'].delete(link)
          result_data['locked_links'].add(link)
        end
      end
    end

    if result_data['links'].empty?
      if !result_data['locked_links'].empty?
        warn_deadend(id, crumbs, vars)
      elsif vars['ending'] != true
        warn_ending(id)
      end
    end

    # End of links; return accumulated link results
    link_results.empty? ? [result_data] : link_results
  end

  def analyze_coverage(results)
    # Each record in `results` contains the breadcrumb trail used to get there,
    # and the final variables arrived at.

    # Empty value Hash of all node IDs in the story.
    node_names = data.keys.reject { |key| key == 'global' }
    counts = node_names.each_with_object({}) { |name, obj| obj[name] = 0 }

    # Iterate through the branches...
    results.each do |path|
      # Iterate through the nodes in the trail.
      path['crumbs'].each do |crumb|
        # Create or add to visit count for each node in the trail.
        counts[crumb] ||= 0
        counts[crumb] += 1
      end
    end

    counts
  end

  def note_proper_ending(id)
    @analysis[:endings] ||= Set.new
    @analysis[:endings].add(id)
  end

  def warn_cycle(id)
    @analysis[:cycles] ||= []
    @analysis[:cycles] += { id: id }
  end

  def warn_deadend(id, crumbs, vars)
    @analysis[:deadends] ||= []
    @analysis[:deadends] += { id: id, crumbs: crumbs, vars: vars }
  end

  def warn_decrement(id, varname, crumbs, vars)
    @analysis[:underflows] ||= []
    @analysis[:underflows] += { id: id, crumbs: crumbs, vars: vars }
  end

  def warn_ending(id)
    @analysis[:unfinished_branches] ||= Set.new
    @analysis[:unfinished_branches].add(id)
  end

  def warn_first_again(id, flagname, crumbs, vars)
    @analysis[:reset_facts] ||= []
    @analysis[:reset_facts] += { id: id, crumbs: crumbs, vars: vars }
  end

  def warn_missing_node(id, linkname)
    @analysis[:missing_links] ||= {}
    @analysis[:missing_links][:linkname] ||= Set.new
    @analysis[:missing_links][:linkname].add({id: linkname})
  end
end
