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

require 'rack/request'
require 'thread'
require 'enumerator'

module Addressive

  class Match < Struct.new(:node,:action,:variables, :spec, :data)
  
    include URIBuilder
  
  end

  # A router which can be used as a rack application and routes requests to nodes and their apps.
  #
  class Router
  
    # @private
    class Tree
    
      # @private
      class Direct < self
      
        class EachingProc < Proc
        
          def initialize(routes)
            @routes = routes
          end
        
          alias each call
          
          def size
            @routes.size
          end
        
        end
      
        def initialize
          @routes = []
        end
      
        def preroute(*_)
          return self
        end
        
        def <<(spec)
          @routes << spec
        end
        
        def clear!
          @routes = []
        end
        
        def size
          @routes.size
        end
        
        def done!
          # compile *gnihihi*
          code = ( 
            ['def each(proto,host,path)',
              'routes = @routes.to_enum',
              'host_path = host + path; proto_host_path = proto + host + path'] +
            @routes.each_with_index.map{|r,i|
              "route = routes.next
              vars = route.template.extract(#{r.template.scheme? ? 'proto_host_path' : (r.template.host? ? 'host_path' : 'path')})
              if vars
                yield( route, vars, #{i+1} )
              end
              "
            } + [ 'end']).join("\n")
          instance_eval(code)
        end
        
        def each(proto,host,path)
          host_path = host + path; proto_host_path = proto + host + path
          @routes.each_with_index do |route,i|
            vars = route.template.extract(route.template.scheme? ? proto_host_path : (route.template.host? ? host_path : path) )
            if vars
              yield( route, vars, i )
            end
          end
        end
      
      end
      
      # @private
      class SubstringSplit < self
      
        def initialize(substring, *partitions)
          @substring = substring
          @partitions = partitions
        end
        
        def preroute(proto,host,path)
          @partitions[ (host+path).include?(@substring) ? 0 : 1 ].preroute(proto,host,path)
        end
        
        def <<(spec)
          if spec.template.send(:tokens).select(&:literal?).none?{|tk| tk.string.include? @substring }
            # okay, this template does not require the substring.
            # so it can be matched, even when the substring is missing
            @partitions[1] << spec
          end
          @partitions[0] << spec
        end
        
        
        def clear!
          @partitions[0].clear!
          @partitions[1].clear!
        end
        
        def done!
          @partitions[0].done!
          @partitions[1].done!
        end
      
      end
      
      # @private
      class PrefixSplit < self
      
        def initialize(prefix, *partitions)
          @prefix = prefix
          @partitions = partitions
        end
        
        def preroute(proto, host, path)
          @partitions[ path.start_with?(@prefix) ? 0 : 1 ].preroute(proto, host, path)
        end
        
        def <<(spec)
          if spec.template.absolute?
            @partitions[0] << spec
            @partitions[1] << spec
          else
            tkns = spec.template.send(:tokens)
            if tkns.empty?
              # emtpy uri, no problem?!
              @partitions[0] << spec
              @partitions[1] << spec
              return
            end
            tk = tkns.first
            if tk.literal?
              if tk.string.start_with?(@prefix)
                @partitions[0] << spec
              elsif @prefix.start_with?(tk.string) and tkns[1]
                @partitions[0] << spec
                @partitions[1] << spec
              else
                @partitions[1] << spec
              end
            else
              @partitions[0] << spec
              @partitions[1] << spec
            end
          end
          
        end
        
        
        def clear!
          @partitions[0].clear!
          @partitions[1].clear!
        end
        
        def done!
          @partitions[0].done!
          @partitions[1].done!
        end
      
      end
    
    end
  
    DEBUG_NAME = 'addressive-router'.freeze
    DEBUG_NULL = lambda{|_| nil}
  
    attr_reader :routes, :actions
  
    def initialize(tree = Tree::Direct.new)
      @routes = []
      @actions = {}
      @tree = tree
      @immaterial = true
      @mutex = Mutex.new
      @sealed = false
    end
    
    # Add a nodes specs to this router.
    def add(*nodes)
      @mutex.synchronize do
        raise "Trying to add nodes to a sealed router!" if @sealed 
        nodes.each do |node|
          node.uri_specs.each do |action, specs|
            specs.each do |spec|
              if spec.valid? and spec.app and spec.route != false
                @routes << spec
                @actions[spec] = [node, action]
              end
            end
          end
        end
        @immaterial = true
      end
      return self
    end
    
    # Routes the env to an app and it's node.
    def call(env)
      rr = Rack::Request.new(env)
      l = env['rack.logger']
      db = l ? l.method(:debug) : DEBUG_NULL
      db.call(DEBUG_NAME) do
        "[ ? ] url: #{rr.url.inspect}, path: #{rr.fullpath.inspect}"
      end
      matches = routes_for(rr.fullpath, rr.url)
      result = nil
      matches.each do |addressive|
        env[ADDRESSIVE_ENV_KEY] = addressive
        begin
          result = (addressive.spec.callback || addressive.spec.app).call(env)
          db.call(DEBUG_NAME) do
            "[#{result[0]}] #{addressive.spec.template.pattern} with #{addressive.variables.inspect} on #{addressive.spec.app} ( route #{addressive.data[:'routes.scanned']} / #{addressive.data[:'routes.total']} ) after #{'%.6f' % addressive.data[:duration]}"
          end
        rescue
          db.call(DEBUG_NAME) do
            "[!!!] #{addressive.spec.template.pattern} with #{addressive.variables.inspect} on #{addressive.spec.app} ( route #{addressive.data[:'routes.scanned']} / #{addressive.data[:'routes.total']} ) after #{'%.6f' % addressive.data[:duration]}"
          end
          raise
        end
        if result[0] != 404
          break
        end
      end
      if result.nil?
        db.call(DEBUG_NAME) do
          "[404] Nothing found"
        end
        return not_found(env)
      end
      return result
    end
    
    class RouteEnumerator
    
      include Enumerable
    
      # @private
      def initialize(routes,proto,host,path,actions)
        @routes,@proto,@host,@path,@actions = routes, proto, host,path, actions
      end
      
      # @yield {Addressive::Match}
      def each
        total = @routes.size
        scan_time = Time.now
        @routes.each(@proto,@host,@path) do |spec, vars, scanned|
          node, action = @actions[spec];
          t = Time.now
          yield Match.new(node, action, vars, spec, {:'routes.scanned'=>scanned,:'routes.total'=>total,:duration => (t - scan_time)})
          # still here?, the passed time should be added
          scan_time += (Time.now - t)
        end
      
      end
    
    end

    URI_SPLITTER = %r{\A([a-z]+:)(//[^/\n]+)(/[^\n]+)\z}

    #
    # @param path String the path to look for
    # @param uri String the full uri
    # @return {RouteEnumerator} an enumerator which yields the requested routes
    def routes_for(path=nil, uri)
      _, *parts = URI_SPLITTER.match(uri).to_a
      raise ArgumentError.new("Expected a valid URI but got #{uri.inspect}") if parts.size != 3
      parts.map!(&:to_s)
      materialize!
      return RouteEnumerator.new(@tree.preroute(*parts),*parts,@actions)
    end
    
    # @private
    def to_app
      return self
    end
    
    # Prevents further editing of this router.
    # This is not mandatory, but encouraged if later changes are not required.
    #
    # @example
    #   rtr = Addressive::Router.new
    #   rtr.add( Addressive.node ) # okay
    #   rtr.seal!
    #   rtr.add( Addressive.node ) #!> Exception
    #
    def seal!
      @mutex.synchronize do
        @sealed = true
      end
      materialize!
    end
    
  protected
    
    # This method is called when no route was found.
    def not_found(env)
      [404,{'Content-Type'=>'text/plain','X-Cascade'=>'pass'},['Ooooopppps 404!']]
    end
    
  private
  
    def materialize!
      return unless @immaterial
      @mutex.synchronize do
        return unless @immaterial
        routes = @routes.sort_by{|spec| [ -spec.template.static_characters, spec.variables.size ] }
        @tree.clear!
        routes.each do |spec|
          @tree << spec
        end
        @tree.done!
        @immaterial = false
      end
    end
  
  end
end
