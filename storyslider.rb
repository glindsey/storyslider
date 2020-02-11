# frozen_string_literals: true

require_relative 'src/story'
require 'ap'

# This should eventually parse STDIN, or take a filename input, or whatever.
# For now, just read and traverse `story.yml`.

story = Story.new('./story.yml')

results = story.traverse('intro')

ap results
