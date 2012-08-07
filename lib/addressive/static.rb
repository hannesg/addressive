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

require 'rack/file'

module Addressive

  # Similiar to Rack::Static but lives happily on a node.
  # Emits just one uri-spec with name ":get" and a simple catch-all uri.
  #
  # @example
  #   node = Addressive.node{
  #     app Addressive::Static.new(:root=>'/tmp')
  #   }
  #   node.uri(:get,'file'=>'baz').to_s #=> "/baz"
  #   
  #   # Create a file, so this won't be a 404:
  #   File.new('/tmp/baz','w').close
  #   router = Addressive::Router.new.add(node)
  #   status,headers,body = router.call('rack.url_scheme'=>'http','PATH_INFO'=>'/baz','HTTP_HOST'=>'example.example','REQUEST_METHOD'=>'GET')
  #   body.class #=> Rack::File
  #   body.path #=> "/tmp/baz"
  #
  class Static
  
    def generate_uri_specs(builder)
    
      builder.uri :get, '/{+file}'
    
    end
    
    def call(env)
      env['PATH_INFO'] = env['addressive'].variables['file']
      return @file_server.call(env)
    end
    
    # @param [Hash] options
    # @option options [#call,Rack::File] :file_server A class compatible to Rack::File. If supplied this will be used instead of the default rack file server
    # @option options [String] :root The directory to search files in. Same as for Rack::File.
    # @option options [Obect] :cache_control Same as for Rack::File.
    def initialize(options={})
      unless options.key? :file_server
        root = options[:root] || Dir.pwd
        cache_control = options[:cache_control]
        @file_server = Rack::File.new(root, cache_control)
      else
        @file_server = options[:file_server]
      end
    end
    
    def to_s
      "Static[#{@file_server.inspect}]"
    end
  
  end

end
