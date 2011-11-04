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

#gem 'uri_template'
$LOAD_PATH << File.expand_path('../../uri_template7/lib',File.dirname(__FILE__))
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
class Addressive < Struct.new(:node,:action,:variables, :spec)

  # This error is raised whenever no uri spec could be found.
  class NoURISpecFound < StandardError
    
    attr_reader :builder
    
    def initialize(builder)
      @builder = builder
      super("No URISpec found for #{builder.inspect}.")
    end
  
  end

  module URIBuilder
  
    def self.new(*args)
      URIBuilderClass.new(*args)
    end
  
    def derive_uri_builder(action, variables, node)
      origin = self.origin rescue nil
      return URIBuilderClass.new( origin, action, variables, node )
    end
    
    protected :derive_uri_builder
  
    # Creates a new URIBuilder with the given arguments.
    # Given Hashes are merged into the variables. The last symbol is used to determine the action. Everything else is used to traverse the node graph.
    # 
    # @example
    #   node = Addressive::Node.new
    #   node.uri_spec(:show) << Addressive::URISpec.new( URITemplate.new('/an/uri/with/{var}') )
    #   bldr = Addressive::URIBuilder.new(node)
    #   bldr.uri(:show, 'var'=>'VAR!').to_s #=> '/an/uri/with/VAR%21'
    #
    # @return URIBuilder
    def uri(*args)
      hashes, path = args.partition{|x| x.kind_of? Hash}
      node = self.node
      action = self.action
      if path.size >= 1
        node = node.traverse(*path[0..-2])
        action = path.last
      end
      derive_uri_builder(action, hashes.inject(self.variables || {}, &:merge), node)
    end
  
    # Actually creates the URI as a string
    #
    # @return String
    def to_s
      specs = self.uri_builder_specs
      # if a.none? ????
      if specs.none?
        raise NoURISpecFound.new(self)
      end
      return specs.first.template.expand(self.variables || {}).to_s
    end
    
    def humanization_key
      specs = self.uri_builder_specs
      if specs.none?
        return super
      else
        return specs.first.app._(:action,self.action,self.variables || {} )
      end
    end
    
    def uri_builder_specs
      return @specs ||= begin
        varnames = (self.variables || {} ).keys
        self.node.uri_spec(self.action).select{|s| s.valid? and (s.variables - varnames).none? }.sort_by{|s| (varnames - s.variables).size }
      end
    end
  
  end

  # A builder which creates uri based on a Node an action and some variables.
  class URIBuilderClass
  
    include URIBuilder

    attr_reader :origin,:node,:variables,:action

    def initialize(origin, action=:default, vars={}, node=origin)
      @origin = origin
      @node = node
      @action = action
      @variables = vars
    end
    
    # @private
    def inspect
      '<URIBuilder '+self.action.inspect+' '+self.variables.inspect+'>'
    end

  end
  
  require 'ostruct'
  
  # A specification is a combination of an URI template and some meta-data ( like the app this spec belongs to ).
  class URISpec < OpenStruct
    
    attr_accessor :template
    
    def valid?
      !!@template
    end
    
    def variables
      @template ? @template.variables : []
    end
    
    def initialize(template, *args)
      @template = template
      super(*args)
    end
    
  end
  
  # A URISpecFactory contains all information necessary to create a URISpec.
  # This class exists because it's annoying to pass around default values by hand and
  # a factory makes it possible to apply post-processing options.
  class URISpecFactory
  
    def converter(defaults = self.all_defaults)
      lambda{|spec|
        if spec.kind_of? URISpec
          [ normalize( spec.dup, defaults ) ]
        elsif spec.kind_of? URITemplate
          [ normalize( URISpec.new( spec ) , defaults) ]
        elsif spec.kind_of? String
          [ normalize( URISpec.new( URITemplate.new(spec) ) , defaults) ]
        elsif spec.kind_of? Array
          spec.map(&self.converter(defaults))
        elsif spec.kind_of? Hash
          nd = defaults.merge(spec)
          self.converter(nd).call(nd[:template])
        else
          []
        end
      }
    end
    
    protected :converter
  
    def normalize( spec, defaults = self.all_defaults )
      if defaults.key? :app 
        spec.app = defaults[:app]
      end
      if defaults[:prefix]
        spec.template = URITemplate.apply( defaults[:prefix] , :/ ,  spec.template)
      end
      return spec
    end
  
    attr_reader :defaults
    
    def initialize(defaults, parent = nil)
      @defaults = defaults
      @parent = parent
    end
    
    def convert(*args)
      args.map(&converter).flatten
    end
    
    alias << convert
    
    def all_defaults
      @parent ? @parent.all_defaults.merge(defaults) : defaults
    end
    
    def derive(nu_defaults)
      self.class.new(nu_defaults, self)
    end
  
  end
  
  # A list of {URISpec}s. Useful because it checks the input.
  class URISpecList
  
    include Enumerable
  
    def initialize(factory, source = [])
      @specs = [] 
      self.<<(*source)
    end
    
    def each(&block)
      @specs.each(&block)
    end
    
    def <<(*args)
      args = args.flatten
      fails = args.select{|a| !a.kind_of? URISpec }
      raise "Expected to receive only URISpecs but, got #{fails.map(&:inspect).join(', ')}" if fails.size != 0
      @specs.push( *args )
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
    
    def inspect
      if @meta['name']
        return "<#{self.class.name}: #{@meta['name']}>"
      else
        super
      end 
    end
  
  end
  
  # A network is basically a hash of nodes and some builder methods.
  # Networks are only used to generate nodes and their relations.
  # They will be GCed when they are done.
  class Network
    
    # An app builder is used to add uris for a certain app to a node.
    class AppBuilder
    
      # @private
      def initialize(node, factory, app)
        @node = node
        @app = app
        @spec_factory = factory
      end
      
      # Sets a default value for an option.
      def default(name, value)
        @spec_factory.defaults[name] = value
      end
      
      # Adds one or more uri specs for a given name. It uses the current app as the default app for all specs.
      def uri(name,*args)
        specs = @node.uri_spec(name)
        specs << @spec_factory.convert(*args)
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
        @spec_factory = network.spec_factory.derive({})
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
        @spec_factory.defaults[name] = value
      end
      
      # Adds one or more uri specs for a given name.
      def uri(name,*args)
        @node.uri_spec(name) << @spec_factory.convert(args)
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
        sf = @spec_factory.derive(options.merge(:app=>app))
        builder = AppBuilder.new(@node,sf,app)
        if block
          if block.arity == 1
            yield builder
          else
            builder.instance_eval(&block)
          end
        end
        unless @node.apps.include? app
          @node.apps << app
          if app.respond_to? :generate_uri_specs
            app.generate_uri_specs(builder)
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
        @network.spec_factory.defaults[name]=value
      end
    
    end
    
    # @private
    def configure(node)
      return node
    end

    # @private
    attr_reader :node_class, :node_builder_class, :spec_factory
    
    # Creates a new Network.
    # @yield {Builder}
    def initialize(&block)
      @defaults = {}
      @node_class = Class.new(Node)
      @node_builder_class = Class.new(NodeBuilder)
      @spec_factory = URISpecFactory.new({})
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
  
  def Network(&block)
    return Network.new(&block)
  end
  
  alias graph Network

  include URIBuilder
  
=begin
  # Later ...
  class Request < Rack::Request
  
    def GET
      if @env['addressive']
        return @env['addressive'].variables
      else
        super
      end
    end
    
    def uri(*args)
      if @env['addressive']
        @env['addressive'].uri(*args)
      else
        self.url
      end
    end
    
  end
=end
  
  # A router which can be used as a rack application and routes requests to nodes and their apps.
  #
  class Router
  
    attr_reader :routes, :actions
  
    def initialize()
      @routes = []
      @actions = {}
    end
    
    # Add a nodes specs to this router.
    def add(node)
      node.uri_specs.each do |action, specs|
        specs.each do |spec|
          if spec.valid? and spec.app and spec.route != false
            @routes << spec
            @actions[spec] = [node, action]
          end
        end
      end
      @routes.sort_by!{|spec| spec.template.static_characters }.reverse!
    end
    
    # Routes the env to an app and it's node.
    def call(env)
      path = env['PATH_INFO'] + (env['QUERY_STRING'].to_s.length > 0 ? '?'+env['QUERY_STRING'] : '')
      best_match = nil
      best_size = 1.0 / 0
      l = env['rack.logger']
      if l
        l.debug('Addressive') do
          "### Start: #{path.inspect}"
        end
      end
      matches = @routes.to_enum.map{|spec| [spec, spec.template.extract(path)] }.reject{|_,v| v.nil?}
      if matches.empty?
        return not_found(env)
      else
        if l
          l.debug('Addressive') do
            matches.each do |spec,variables|
              "# found: #{spec.template.pattern.inspect} with #{variables.inspect}"
            end
          end
        end
        spec, variables = matches.first
        node, action = @actions[spec]
        env['addressive']=Addressive.new(node, action, variables, spec)
        return spec.app.call(env)
      end
    end
  
    # This method is called when no route was found.
    # You may override this as you wish.
    def not_found(env)
      [404,{'Content-Type'=>'text/plain'},['Ooooopppps 404!']]
    end
    
    # @private
    def to_app
      return self
    end
  
  end

end
