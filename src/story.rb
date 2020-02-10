# frozen_string_literals: true

require 'pry'
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

        vars[flagname] = value
      end
    end

    if node['values'].is_a?(Hash)
      node['values'].each do |(varname, rules)|
        raise TypeError, 'expected Hash' unless rules.is_a?(Hash)

        op = rules['op'].to_s
        num = rules['value'].to_i
        raise TypeError, 'value must be numeric' unless num.is_a?(Integer)

        case op
        when '='
          vars[varname] = num
        when '-'
          vars[varname] -= num
          warn_decrement(node, varname) if vars[varname] < 0
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
              raise TypeError, 'expected Hash' unless rules.is_a?(Hash)

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
                raise TypeError, "invalid comparison operator '#{op}' provided"
              end
            end
          end
        end

        if can_visit
          link_results.concat(
            traverse(link, vars, crumbs)
          )
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
        warn_ending(id, crumbs, vars)
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
    warn "Node #{id} was already visited in this branch; " \
         "bailing out of possible cycle"
  end

  def warn_deadend(id, crumbs, vars)
    warn "Dead end encountered at node ID '#{id}' -- all links locked"
    warn "Breadcrumb trail: #{crumbs}"
    warn "Variables: #{vars}"
  end

  def warn_decrement(id, varname)
    warn "Node ID '#{id}' -- decrementing '#{varname}' drops it below zero"
  end

  def warn_ending(id, crumbs, vars)
    warn "Dead end encountered at node ID '#{id}' -- " \
         "no links present and ending flag not set"
    warn "Breadcrumb trail: #{crumbs}"
    warn "Variables: #{vars}"
  end
end
