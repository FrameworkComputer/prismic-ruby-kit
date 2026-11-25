# encoding: utf-8
require 'nokogiri'

RSpec.configure do |c|
  # Stop after the first failure
  # c.fail_fast = true
  c.filter_run_excluding live: true unless ENV['LIVE']
end

$LOAD_PATH << File.join(File.dirname(__FILE__), '..', 'lib')

require 'prismic'
