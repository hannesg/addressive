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

module Addressive

  # A graph is basically a hash of nodes and some builder methods.
  # Graphs are only used to generate nodes and their relations.
  # They will be GCed when they are done.
  class Graph
    
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
    
    # A NodeBuilder is used to build a Node inside a Graph.
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
      #   nw = Addressive::Graph.new{
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
      #   Addressive::Graph.new{
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
    # It's here so that a {Graph} can have only read methods, while a {Builder} does the heavy lifting.
    # This class should not be generated directly, it's created for you by {Graph#build} and {Graph#initialize}.
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
    
    # Creates a new Graph.
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
    #   A Graph will automatically create nodes if they don't exists.
    def [](name)
      return @nodes[name]
    end
  
    alias node []
  
  end
end
