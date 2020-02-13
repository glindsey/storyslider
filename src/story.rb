# frozen_string_literals: true

require 'concurrent'
require 'pry'
require 'set'
require 'yaml'

require_relative 'boolean_superposition'
require_relative 'breadcrumb'
require_relative 'minmax'
require_relative 'utilities'

class Story
  attr_reader :data

  include Utilities

  def initialize(filename)
    warn "Loading YAML data from #{filename}..."
    @data = YAML.load_file(filename)

    warn "Normalizing data..."
    @data = clean_story_data!(@data)
  end

  def analyze
    warn "Running traversal..."
    results, analysis = traverse('intro')

    warn "Running coverage analysis..."
    coverage = analyze_coverage(results)
    zero_visits = coverage.select { |_, num| num == 0 }.keys

    zero_visit_reasons = zero_visits.each_with_object({}) do |node, result|
      sources = analysis[:backlinks][node].to_a
      result[node] = sources.map do |source|
        source_node = data[source]
        links = source_node['links']
        conditions = links[node]
        flag_conditions = conditions['flags'] || {}
        value_conditions = conditions['values'] || {}
        flag_info = flag_conditions.each_with_object({}) do |(flag_name, flag_condition), info|
          info[flag_name] = { condition: flag_condition, actual: possible_vars[source][flag_name] }
        end
        value_info = value_conditions.each_with_object({}) do |(value_name, value_condition), info|
          info[value_name] = { condition: value_condition, actual: possible_vars[source][value_name] }
        end

        flag_info.merge(value_info)
      end
    end

    analysis[:issues][:never_hit] = zero_visit_reasons

    [results, analysis]
  end

  def clean_story_data!(data)
    raise TypeError, "expected data to be Hash" unless data.is_a?(Hash)

    data.each do |(id, node)|
      if node['flags'].is_a?(Hash)
        node['flags'].each do |(flagname, value)|
          node['flags'][flagname] = clean_flag(id, flagname, value)
        end
      end

      if node['values'].is_a?(Hash)
        node['values'].each do |(varname, rules)|
          node['values'][varname] = clean_value(id, varname, rules)
        end
      end

      if node['links'].is_a?(Hash)
        node['links'].each do |(linkname, conditions)|
          if conditions['flags'].is_a?(Hash)
            conditions['flags'].each do |(flagname, value)|
              conditions['flags'][flagname] = clean_flag(id, flagname, value)
            end
          end

          if conditions['values'].is_a?(Hash)
            conditions['values'].each do |(varname, rules)|
              conditions['values'][varname] = clean_value(id, varname, rules)
            end
          end
        end
      end
    end
  end

  def traverse(id, vars_orig = {}, crumbs_orig = [], analysis = {})
    id = id.to_s if id.is_a?(Symbol)

    raise TypeError, "#{id}: expected id to be String" unless id.is_a?(String)

    raise TypeError, "#{id}: expected vars to be Hash" unless vars_orig.is_a?(Hash)

    raise TypeError, "#{id}: expected crumbs to be Array" unless crumbs_orig.is_a?(Array)

    # Duplicate the node/vars at this level.
    vars = vars_orig.dup
    crumbs = crumbs_orig.dup

    crumbs.push(Breadcrumb.new(id, vars))

    node = data[id]

    raise TypeError, "#{id}: expected node to be Hash" unless node.is_a?(Hash)

    result_data = {
      'crumbs' => crumbs,
      'vars' => vars
    }

    # First check if the node was already visited.
    crumbs_orig.reverse_each do |crumb|
      if crumb.id == id && crumb.vars == vars
        warn_cycle!(id, crumbs.map(&:id), vars, analysis)
        return [result_data]
      end
    end

    if node['flags'].is_a?(Hash)
      node['flags'].each do |(flagname, value)|
        if vars[flagname] == true && flagname.start_with?('first_')
          warn_first_again!(id, flagname, crumbs.map(&:id), vars, analysis)
        end

        vars[flagname] = value
      end
    end

    if node['values'].is_a?(Hash)
      node['values'].each do |(varname, rules)|
        op = rules['op'].to_s
        num = rules['value'].to_i

        case op
        when '='
          vars[varname] = num
        when '-'
          vars[varname] ||= 0
          vars[varname] -= num
          if vars[varname] < 0
            warn_decrement!(id, varname, crumbs.map(&:id), vars, analysis)
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
    analysis[:possible_vars] ||= {}
    vars.each do |(varname, varvalue)|
      analysis[:possible_vars][id] ||= {}

      # TODO: this will fail if a var is a flag in one node and a number in
      #       another, should handle that more error condition more gracefully
      case varvalue
      when FalseClass, TrueClass
        analysis[:possible_vars][id][varname] ||= BooleanSuperposition.new(varvalue)
      when Integer
        analysis[:possible_vars][id][varname] ||= MinMax.new(varvalue, varvalue)
      end

      analysis[:possible_vars][id][varname] += varvalue
    end

    link_ids = Set.new((node['links'] || {}).keys)
    result_data['links'] = link_ids
    result_data['locked_links'] = Set.new

    link_results = []
    if node['links'].is_a?(Hash)
      node['links'].each do |(link, conditions)|
        analysis[:backlinks] ||= {}
        analysis[:backlinks][link] ||= Set.new
        analysis[:backlinks][link].add(id)

        can_visit = true
        if conditions.is_a?(Hash)
          flag_conditions = conditions['flags'] || {}
          value_conditions = conditions['values'] || {}

          flag_conditions.each do |(flagname, value)|
            can_visit &= ((vars[flagname] || false) == value)
          end

          if value_conditions.is_a?(Hash)
            value_conditions.each do |varname, rules|
              op = rules['op'].to_s
              num = rules['value'].to_i

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
          warn_missing_node!(id, link, analysis)
        elsif can_visit
          results, analysis = traverse(link, vars, crumbs, analysis)
          link_results.concat(results)
        else
          result_data['links'].delete(link)
          result_data['locked_links'].add(link)
        end
      end
    end

    if result_data['links'].empty?
      if !result_data['locked_links'].empty?
        warn_deadend!(id, crumbs.map(&:id), vars, analysis)
      elsif vars['ending'] != true
        warn_ending!(id, analysis)
      end
    end

    # End of links; return accumulated link results and analysis data
    [(link_results.empty? ? [result_data] : link_results), analysis]
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
        counts[crumb.id] ||= 0
        counts[crumb.id] += 1
      end
    end

    counts
  end

  def note_proper_ending(id, analysis)
    analysis[:endings] ||= Set.new
    analysis[:endings].add(id)
  end

  def warn_cycle!(id, trail, vars, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:cycles] ||= []
    analysis[:issues][:cycles].push(
      {
        id: id,
        trail: print_trail(trail),
        vars: vars
      }
    )
  end

  def warn_deadend!(id, trail, vars, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:deadends] ||= []
    analysis[:issues][:deadends].push(
      {
        id: id,
        trail: print_trail(trail),
        vars: vars
      }
    )
  end

  def warn_decrement!(id, varname, trail, vars, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:underflows] ||= []
    analysis[:issues][:underflows].push(
      {
        id: id,
        trail: print_trail(trail),
        vars: vars
      }
    )
  end

  def warn_ending!(id, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:unfinished_branches] ||= Set.new
    analysis[:issues][:unfinished_branches].add(id)
  end

  def warn_first_again!(id, flagname, trail, vars, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:reset_facts] ||= []
    analysis[:issues][:reset_facts].push(
      {
        id: id,
        trail: print_trail(trail),
        vars: vars
      }
    )
  end

  def warn_missing_node!(id, linkname, analysis)
    analysis[:issues] ||= {}
    analysis[:issues][:missing_links] ||= {}
    analysis[:issues][:missing_links][:linkname] ||= Set.new
    analysis[:issues][:missing_links][:linkname].add({id: linkname})
  end

  def print_trail(trail)
    trail.join(' -> ')
  end

  def clean_flag(id, flagname, value)
    case value
    when String
      cleaned_val = value.lowercase.strip
      if ['y', 't', 'yes', 'true'].include?(cleaned_val)
        true
      elsif ['n', 'f', 'no', 'false'].include?(cleaned_val)
        false
      else
        raise TypeError,
              "#{id}: flag #{flagname}: don't know how to interpret " \
              "'#{value}'"
      end
    when Integer
      if value == 0
        warn "#{id}: flag #{flagname} has value 0, interpreting as false"
        false
      elsif value == 1
        warn "#{id}: flag #{flagname} has value 1, interpreting as true"
        true
      else
        raise TypeError,
              "#{id}: flag #{flagname}: don't know how to interpret " \
              "integer #{value}"
      end
    when TrueClass, FalseClass
      # This is okay.
      value
    else
      raise TypeError,
            "#{id}: value of flag #{flagname} is of unknown " \
            "type #{value.class.name}"
    end
  end

  def clean_value(id, varname, rules)
    op = ''
    num = 0

    case rules
    when String
      rules.strip!
      tokens = rules.split(/\b/).map(&:strip)
      case tokens[0]
      when '=', '-', '+', '==', '<', '>'
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
      raise TypeError,
            "#{id}: expected #{rules} to be String, Integer, or Hash"
    end

    { 'op' => op, 'value' => num }
  end
end
