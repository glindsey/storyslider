# frozen_string_literals: true

require 'pry'
require 'set'
require 'yaml'

class Story
  attr_accessor :data

  def initialize(filename)
    @data = YAML.load_file(filename)
  end

  def traverse(id, vars_orig = {}, crumbs_orig = [])
    id = id.to_s if id.is_a?(Symbol)

    raise TypeError, 'expected id to be String' unless id.is_a?(String)

    raise TypeError, 'expected vars to be Hash' unless vars_orig.is_a?(Hash)

    raise TypeError, 'expected crumbs to be Array' unless crumbs_orig.is_a?(Array)

    vars = vars_orig.dup
    crumbs = crumbs_orig.dup

    crumbs.push(id)

    # Duplicate the node/vars at this level.
    node = data[id]

    raise TypeError, 'expected node to be Hash' unless node.is_a?(Hash)

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
          raise TypeError, 'flag must be true or false'
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
            raise TypeError, "don't know how to parse '#{rules}'"
          end
        when Integer
          op = '='
          num = rules
        when Hash
          op = rules['op'].to_s
          num = rules['value'].to_i
        else
          raise TypeError, "expected #{rules} to be String, Integer, or Hash"
        end

        case op
        when '='
          vars[varname] = num
        when '-'
          vars[varname] -= num
          warn_decrement(node, varname, crumbs, vars) if vars[varname] < 0
        when '+'
          vars[varname] += num
        else
          raise TypeError, "invalid operator '#{op}' provided"
        end
      end
    end

    link_ids = Set.new((node['links'] || {}).keys)
    result_data['links'] = link_ids
    result_data['locked_links'] = Set.new

    link_results = []
    if node['links'].is_a?(Hash)
      node['links'].each do |(link, conditions)|
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
                  raise TypeError, "don't know how to parse '#{rules}'"
                end
              when Integer
                op = '=='
                num = rules.to_i
              when Hash
                op = rules['op'].to_s
                num = rules['value'].to_i
              else
                raise TypeError,
                      "expected #{rules} to be String, Integer, or Hash"
              end

              case op
              when '=', '=='
                can_visit &= ((vars[varname] || 0) == num)
              when '<'
                can_visit &= ((vars[varname] || 0) < num)
              when '>'
                can_visit &= ((vars[varname] || 0) > num)
              else
                raise TypeError, "invalid comparison operator '#{op}' provided"
              end
            end
          end
        end

        if !data.key?(link)
          warn_missing_node(id, link)
          can_visit = false
        end

        if can_visit
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
    story_nodes = data.each_with_object({}) { |node, obj| obj[node] = {} }

    # Iterate through the branches...
    results.each do |path|
      # Iterate through the nodes in the trail.
      path['crumbs'].each do |crumb|
        # Create or add to visit count for this node.
        story_nodes[crumb]['visit_count'] ||= 0
        story_nodes[crumb]['visit_count'] += 1
      end
    end

    { nodes: story_nodes }
  end

  def warn_cycle(id)
    warn "#{id}: Node was already visited in this branch; " \
         "bailing out of possible cycle"
  end

  def warn_deadend(id, crumbs, vars)
    warn "#{id}: Dead end encountered -- all links locked"
    print_context(id, crumbs, vars)
  end

  def warn_decrement(id, varname, crumbs, vars)
    warn "#{id}: Decrementing '#{varname}' drops it below zero"
    print_context(id, crumbs, vars)
  end

  def warn_ending(id)
    warn "#{id}: Dead end encountered -- " \
         "no links present and 'ending' flag not set"
  end

  def warn_first_again(id, flagname, crumbs, vars)
    warn "#{id}: Previously set flag #{flagname} was reset"
    print_context(id, crumbs, vars)
  end

  def warn_missing_node(id, linkname)
    warn "#{id}: Links to missing node #{linkname}"
  end

  def print_context(id, crumbs, vars)
    warn "#{' ' * id.length}  Breadcrumb trail: #{crumbs}"
    warn "#{' ' * id.length}  Variables: #{vars}"
  end
end
