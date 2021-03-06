# -*- encoding : utf-8 -*-
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the Affero GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#    (c) 2011 by Hannes Georg
#

require 'bundler'
require "rubygems"
require "bundler/setup"

Bundler.require(:default,:development)

begin
  require 'simplecov'
  SimpleCov.add_filter('spec')
  SimpleCov.start
rescue LoadError
  warn 'Not using simplecov.'
end

class Addressive::NativeImplementationMatcher

  def matches?( actual )
    @actual = actual
    return true if @actual.source_location.nil?
    if RUBY_DESCRIPTION =~ /\Arubinius /
      return @actual.source_location[0] =~ /\Akernel\//
    end
    return false
  end

  def failure_message_for_should
    return [@actual.inspect, ' should be natively implemented, but was found in ', @actual.source_location.inspect ].join 
  end

end

RSpec::Matchers.class_eval do
  def be_native
    return Addressive::NativeImplementationMatcher.new
  end
end