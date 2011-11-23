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

$LOAD_PATH << File.expand_path('../../uri_template7/lib/',File.dirname(__FILE__))
require File.expand_path('../../uri_template7/lib/uri_template',File.dirname(__FILE__))
require 'ostruct'

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

  autoload :Static, 'addressive/static'
  autoload :Request, 'addressive/request'
  autoload :Router, 'addressive/router'
  autoload :Graph, 'addressive/graph'

  ADDRESSIVE_ENV_KEY = 'addressive'.freeze

  class Error < StandardError
  
  end

  # This error is raised whenever no uri spec could be found.
  class NoURISpecFound < Error
    
    attr_reader :builder
    
    def initialize(builder)
      @builder = builder
      super("No URISpec found for #{builder.inspect}. Only got: #{builder.node.uri_specs.keys.join(', ')}")
    end
  
  end
  
  class NoEdgeFound < Error
  
    attr_reader :node, :edge
    
    def initialize(node, edge)
      @node, @edge = node, edge
      super("No Edge '#{edge.inspect}' found, only got '#{node.edges.keys.map(&:inspect).join('\', \'')}'")
    end
  
  end

  # A module for any class, which can create uris.
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
      return uri_builder_delegate.uri(*args) if uri_builder_delegate
      hashes, path = args.collect_concat{|a| a.respond_to?(:to_addressive) ? a.to_addressive : [a] }.partition{|x| x.kind_of? Hash}
      node = self.node
      action = self.action
      if path.size >= 1
        node = node.traverse(*path[0..-2])
        action = path.last
      end
      derive_uri_builder(action, hashes.inject(self.variables || {}, &:merge), node)
    end
    
    private
    
    def uri_builder_delegate
      nil
    end
  
  end

  # A builder which creates uri based on a Node an action and some variables.
  class URIBuilderClass
  
    include URIBuilder

    attr_reader :origin,:node,:variables,:action

    # @private
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
    
    # Actually creates the URI as a string
    #
    # @return String
    def to_s
      return uri_builder_delegate.to_s if uri_builder_delegate
      specs = uri_builder_specs
      # if a.none? ????
      if specs.none?
        raise NoURISpecFound.new(self)
      end
      return specs.first.template.expand(self.variables || {}).to_s
    end
    
    def humanization_key
      specs = uri_builder_specs
      if specs.none?
        return super
      else
        return specs.first.app._(:action,self.action,self.variables || {} )
      end
    end
  private
    def uri_builder_specs
      return @specs ||= begin
        varnames = (self.variables || {} ).keys
        self.node.uri_spec(self.action).select{|s| s.valid? and (s.variables - varnames).none? }.sort_by{|s| (varnames - s.variables).size }
      end
    end
  end
  
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
    
    def inspect
      ['#<',self.class.name,': ',template.inspect,*@table.map{|k,v| " #{k}=#{v.inspect}"},'>'].join
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
      unless spec.template.absolute?
        if defaults[:prefix]
          spec.template = URITemplate.apply( defaults[:prefix] , :/ ,  spec.template)
        end
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
      raise ArgumentError, "Expected to receive only URISpecs but, got #{fails.map(&:inspect).join(', ')}" if fails.size != 0
      @specs.push( *args )
    end
    
    alias push <<
  
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
    
    include URIBuilder
  
    def initialize
      @edges = {}
      @meta = {}
      @apps = []
      @uri_specs = Hash.new{|hsh,name| hsh[name]=URISpecList.new(@defaults) }
      @uri_builder_delegate = URIBuilder.new(self)
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
        raise NoEdgeFound.new(self, args.first)
      end
    end
    
    def uri_spec(name)
      @uri_specs[name]
    end
    
    def inspect
      if @meta['name']
        return "<#{self.class.name}: #{@meta['name']}>"
      else
        super
      end 
    end
    
  private
    def uri_builder_delegate
      @uri_builder_delegate
    end
  
  end
  
  # Creates a new node and yields a builder for it
  #
  # This method makes it easy to create a tree-like structur by implictly creating and returning a root node ( by default called :root ). This should be used in most cases, as you will likely have just one connected component in an addressive graph. For complexer graphs you can use {Addressive#graph}.
  #
  # @example
  #   node = Addressive.node do 
  #     edge( :another ) do
  #       default :prefix, '/another'
  #       uri :default ,'/'
  #     end
  #     uri :default ,'/'
  #   end
  #   
  #   node.uri.to_s #=> '/'
  #   node.uri(:another,:default).to_s #=> '/another/'
  #
  # @param name [Symbol] a name for this node
  # @yield {NodeBuilder}
  # @return {Graph}
  #
  def self.node(name=:root,&block)
    Graph.new{ |bldr|
      bldr.node name, &block
    }[name]
  end
  
  # Creates a new graph and yields a builder for it
  #
  # This is good, if you want to create a graph with disconnected nodes or multiple root-nodes.
  #
  # @example
  #   graph = Addressive.graph do
  #     
  #     node :shared do
  #       uri :default, '/shared'
  #     end
  #     
  #     node :foo do
  #       uri :default ,'/foo'
  #       edge :shared
  #     end
  #     
  #     node :bar do
  #       uri :default, '/bar'
  #       edge :shared
  #     end
  #     
  #   end
  #   
  #   # You can then get the nodes with {Addressive::Graph.[]}
  #   graph[:foo].uri.to_s #=> '/foo'
  #   graph[:bar].uri.to_s #=> '/bar'
  #   # :foo and :bar can both reach :shared, but not each other.
  #   # Neither can :shared reach any other node.
  #   graph[:foo].traverse(:shared) #=> graph[:shared]
  #   graph[:bar].traverse(:shared) #=> graph[:shared]
  #   graph[:foo].traverse(:bar) #!> Addressive::NoEdgeFound
  #   graph[:shared].traverse(:bar) #!> Addressive::NoEdgeFound
  #
  # @yield {Builder}
  # @return {Node}
  #
  def self.graph(&block)
    Graph.new(&block)
  end

end

