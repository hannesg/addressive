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

gem 'uri_template'
require 'uri_template'

# Addressive is library which should make it possible for different rack-applications to live together on the same server.
# To accomplish this, addressive supplies you with:
#   - A model for a graph in which each node is one application.
#   - A template-based uri-builder which is aware of the network and can generate uri for any reachable application.
#   - A router which can route rack-requests based on the known templates.
#
# What needs to be done by the apps:
#   - Provide uri templates.
#
module Addressive

  # This error is raised whenever no uri spec could be found.
  class NoURISpecFound < StandardError
    
    attr_reader :builder
    
    def initialize(builder)
      @builder = builder
      super("No URISpec found for #{builder.inspect}.")
    end
  
  end

  # A builder which creates uri based on a Node an action and some variables.
  class URIBuilder

    attr_reader :origin,:node,:variables,:action

    def initialize(origin, action=:default, vars={}, node=origin)
      @origin = origin
      @node = node
      @action = action
      @variables = vars
    end
  
    # Creates a new URIBuilder with the given arguments.
    # Given Hashes are merged into the variables. The last symbol is used to determine the action. Everything else is used to traverse the node graph.
    # 
    # @example
    #   node = Addressive::Node.new
    #   node.uri_spec(:show) << '/an/uri/with/{var}'
    #   bldr = Addressive::URIBuilder.new(node)
    #   bldr.uri(:show, 'var'=>'VAR!').to_s #=> '/an/uri/with/VAR%21'
    #
    # @return URIBuilder
    def uri(*args)
      hashes, path = args.partition{|x| x.kind_of? Hash}
      node = @node
      action = @action
      if path.size >= 1
        node = node.traverse(*path[0..-2])
        action = path.last
      end
      URIBuilder.new(@origin, action, hashes.inject(@variables, &:merge), node)
    end

    # @private
    alias to_s_without_uri to_s
  
    # Actually creates the URI as a string
    #
    # @return String
    def to_s
      varnames = @variables.keys
      specs = @node.uri_spec(@action).select{|spec| spec.valid?}.sort_by{|s| (s.variables & varnames).size }
      # if a.none? ????
      if specs.none?
        raise NoURISpecFound.new(self)
      end
      return specs.last.template.expand(@variables).to_s
    end
    
    # @private
    def inspect
      '<URIBuilder '+ @node.inspect+' '+@action.inspect+' '+@variables.inspect+'>'
    end

  end
  
  # A specification is a combination of an URI template and some meta-data ( like the app this spec belongs to ).
  class URISpec
    
    attr_reader :template, :options
    
    def valid?
      !!@template
    end
    
    def variables
      @template ? @template.variables : []
    end
    
    def pattern
      @options['pattern']
    end
    
    def app
      @options['app']
    end
    
    def app=(app)
      @options['app']=app
    end
    
    def initialize(options)
      @options = options
      if options['template'].kind_of? URITemplate
        @template = options['template']
        @options['pattern'] = @template.pattern
        #@options['type'] = @template.type
      elsif options['pattern']
        begin
          @template = URITemplate.new(options['pattern'],options.fetch('type',:default).to_sym)
        rescue URITemplate::Invalid => ex
          @error = ex.message
          @template = nil
        end
      end
    end
    
    def [](key)
      return @options[key]
    end
    
    def export
      return @options
    end
    
  end
  
  class URISpecList
  
    include Enumerable
  
    def self.converter(defaults)
      lambda{|spec|
        if spec.kind_of? URISpec
          spec
        elsif spec.kind_of? URITemplate
          URISpec.new( defaults.merge('template'=>spec) )
        elsif spec.kind_of? String
          URISpec.new( defaults.merge('pattern'=>spec) )
        elsif spec.kind_of? Array
          spec.map(&self.converter(defaults))
        elsif spec.kind_of? Hash
          nd = defaults.merge(spec)
          self.converter(nd).call(nd['pattern'])
        else
          []
        end
      }
    end
    
    def convert(*args)
      args.map(&self.class.converter(@defaults)).flatten
    end
  
    def initialize(defaults, source = [])
      @defaults = defaults
      @specs = [] 
      self.<<(*source)
    end
    
    def each(&block)
      @specs.each(&block)
    end
    
    def <<(*args)
      @specs.push( *convert(args) )
    end
    
    alias push <<
    
    def export
      self.map(&:export)
    end
  
  end
  
  # The node is the most important class. A node bundles informations about all uri specs for a certain application.
  # Furthermore nodes can reference each other so that one can traverse them.
  #
  # @example
  #   node1 = Addressive::Node.new
  #   node2 = Addressive::Node.new
  #   node1.edges[:another_node] = node2
  #   node1.traverse(:another_node) #=> node2
  #
  class Node
  
    attr_reader :edges, :meta, :uri_specs
    attr_reader :apps
    attr_accessor :defaults
  
    def initialize
      @edges = {}
      @meta = {}
      @defaults = {}
      @apps = []
      @uri_specs = Hash.new{|hsh,name| hsh[name]=URISpecList.new(@defaults) }
    end
    
    # Traverses some edges to another ( or the same ) node.
    # 
    # @example
    #   node1 = Addressive::Node.new
    #   node2 = Addressive::Node.new
    #   node3 = Addressive::Node.new
    #   node1.edges[:n2] = node2
    #   node2.edges[:n3] = node3
    #   node3.edges[:n1] = node1
    #   node1.traverse() #=> node1
    #   node1.traverse(:n2) #=> node2
    #   node1.traverse(:n2,:n3,:n1) #=> node1
    #
    def traverse(*args)
      return self if args.none?
      if edges[args.first].kind_of? Addressive::Node
        return edges[args.first].traverse(*args[1..-1])
      else
        raise ArgumentError, "Can't traverse to #{args.first.inspect}, only got #{edges.keys.inspect}."
      end
    end
    
    def uri_spec(name)
      @uri_specs[name]
    end
    
    # Shorthand to generate an URIBuilder for this Node.
    def uri(*args)
      URIBuilder.new(self).uri(*args)
    end
    
    def export
      return {'meta'=>meta,
        'defaults'=>defaults,
        'uri_specs'=>Hash[ *@uri_specs.map{|k,v| [k.to_s,v.export] }.select{|k,v| v.any? }.flatten(1) ]
      }
    end
    
    def import(data)
      @meta.update(data.fetch('meta',{}))
      @defaults.update(data.fetch('defaults',{}))
      data.fetch('uri_specs',{}).map{|k,v|
        uri_spec(k.to_sym) << v
      }
      
    end
  
  end
  
  # A network is basically a hash of nodes and some builder methods.
  # Networks are only used to generate nodes and their relations.
  # They will be GCed when they are done.
  class Network
    
    # An app builder is used to add uris for a certain app to a node.
    class AppBuilder
    
      # @private
      def initialize(node, app)
        @node = node
        @app = app
      end
      
      # Adds one or more uri specs for a given name. It uses the current app as the default app for all specs.
      def uri(name,*args)
        specs = @node.uri_spec(name)
        specs << specs.convert(*args).each{|spec| spec.app = @app }
        return specs
      end
    
    end
    
    # A NodeBuilder is used to build a Node inside a Network.
    # This class should not be generated directly, it's created for you by {Builder#node}.
    class NodeBuilder
  
      attr_reader :node
      
      # @private
      def initialize(network,node)
        @network = network
        @node = node
      end
      
      # Adds an edge from the current node to a node with the given name.
      # 
      # @example
      #   nw = Addressive::Network.new{
      #     #create a node named :app_a
      #     node :app_a do
      #       # Creates an edge to the node named :app_b. The name of the edge will be :app_b, too.
      #       edge :app_b 
      #
      #       # Creates another edge to the node named :app_b with edge name :app_c.
      #       edge :app_c, :app_b
      #
      #       # Edge takes a block. Same behavior as Builder#node.
      #       edge :app_d do
      #         
      #         edge :app_a
      #       
      #       end
      #     end
      #   }
      #   # :app_a now references :app_b twice, :app_d once and is referenced only by :app_d.
      #
      # @yield BlockBuilder
      #
      def edge(as , name = as, &block)
        @node.edges[as] = @network.build.node(name,&block).node
        return self
      end
      
      alias ref edge
      
      # Sets a default value for an option.
      def default(name, value)
        @node.defaults[name] = value
      end
      
      # Adds one or more uri specs for a given name.
      def uri(name,*args)
        @node.uri_spec(name).<<(*args)
        return @node.uri_spec(name)
      end
      
      # Adds an rack-application to this node.
      #
      # @example
      #
      #   Addressive::Network.new{
      #     
      #     node :a_node do
      #       
      #       app lambda{|env| [200,{},['App 1']]} do
      #         uri :show, '/a_node/app1'
      #       end
      #       
      #       app lambda{|env| [200,{},['App 2']]} do
      #         uri :show, '/a_node/app2'
      #       end
      #     
      #     end
      #   
      #   }
      #
      # @yield {AppBuilder}
      # @return {AppBuilder}
      def app(app, options = {}, &block)
        app = app.to_app if app.respond_to? :to_app
        unless @node.apps.include? app
          @node.apps << app
          if app.respond_to? :generate_uri_specs
          puts app.generate_uri_specs(options).inspect
            app.generate_uri_specs(options).each do |k,v|
              specs = @node.uri_spec(k)
              specs << specs.convert(v).each{|spec| spec.app ||= app }
            end
          end
        end
        builder = AppBuilder.new(@node,app)
        if block
          if block.arity == 1
            yield builder
          else
            builder.instance_eval(&block)
          end
        end
        return builder
      end
      
    end
  
    # A Builder is used to construct a network.
    # It's here so that a {Network} can have only read methods, while a {Builder} does the heavy lifting.
    # This class should not be generated directly, it's created for you by {Network#build} and {Network#initialize}.
    class Builder
      
      # @private
      def initialize(network)
        @network = network
      end
    
      # Creates or edits the node with the given name in the current network and yields and returns a NodeBuilder.
      # This NodeBuilder can then be use to actually describe the node.
      #
      # @yield {NodeBuilder}
      # @return {NodeBuilder}
      def node(name, &block)
        n = @network.node(name)
        if block
          if block.arity == 1
            yield @network.node_builder_class.new(@network, n)
          else
            @network.node_builder_class.new(@network, n).instance_eval(&block)
          end
        end
        return @network.node_builder_class.new(@network, n)
      end
      
      # Sets a network-wide default.
      # @note
      #   Only nodes created after this default has been set will receive this value.
      #
      def default(name,value)
        @network.defaults[name]=value
      end
    
    end
    
    # @private
    def configure(node)
      node.defaults.update(@defaults)
      return node
    end

    # @private
    attr_reader :node_class, :node_builder_class, :defaults
    
    # Creates a new Network.
    # @yield {Builder}
    def initialize(&block)
      @defaults = {}
      @node_class = Class.new(Node)
      @node_builder_class = Class.new(NodeBuilder)
      @nodes = Hash.new{|hsh, name| hsh[name] = configure(node_class.new) }
      build(&block)
    end
    
    # Creates, yields and returns a {Builder} for this network.
    #
    # @yield {Builder}
    # @return {Builder}
    def build(&block)
      if block
        if block.arity == 1
          yield Builder.new(self)
        else
          Builder.new(self).instance_eval(&block)
        end
      end
      return Builder.new(self)
    end
    
    # Return the node with the given name.
    # @note
    #   A Network will automatically create nodes if they don't exists.
    def [](name)
      return @nodes[name]
    end
  
    alias node []
  
  end
  
  # A router which can be used as a rack application and routes requests to nodes and their apps.
  #
  class Router
  
    attr_reader :routes
  
    def initialize()
      @routes = []
    end
    
    # Add a nodes specs to this router.
    def add(node)
      node.uri_specs.each do |action, specs|
        specs.each do |spec|
          if spec.valid? and spec.app and spec.options.fetch('route',true)
            @routes << [node, action, spec]
          end
        end
      end
    end
    
    # Routes the env to an app and it's node.
    def call(env)
      path = env['PATH_INFO']
      best_match = nil
      best_size = 1.0 / 0
      @routes.each{|node, action, spec|
        spec.template.extract(path){ |vars|
          if vars.size < best_size
            best_match = {variables: vars, node: node, spec: spec, action: action}
            best_size = vars.size
          end
        }
      }
      if best_match
        return best_match[:spec].app.call(env.merge({'addressive'=>best_match}))
      else
        return not_found(env)
      end
    end
  
    # This method is called when no route was found.
    # You may override this as you wish.
    def not_found(env)
      [404,{},['']]
    end
    
    # @private
    def to_app
      return self
    end
  
  end

end
