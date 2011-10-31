require 'addressive'
require 'weakref'
describe Addressive do

  describe Addressive::Network do
  
    before(:each){
    
      @nw = Addressive::Network.new
      
      @nw.build.default('type','default')
      
      @nw.build.node(:frontend){
        
        ref :backend
        ref :remote
        
      }
      
      @nw.build.node(:backend){
        
        ref :frontend
        
      }
      
      @nw.build.node(:remote){
        
      }
    
    }
  
    it "should draw networks" do
    
      
    
      @nw[:frontend].should be_kind_of(Addressive::Node)
      
      @nw[:frontend].edges[:backend].should be_kind_of(Addressive::Node)
      
      @nw[:frontend].edges[:backend].should == @nw[:backend]
      
    end
  
    it "should be able to add uri specs" do
    
      @nw.build.node(:frontend){
      
        uri(:show, '/show{?args*}')
      
      }
      
      @nw[:frontend].uri_spec(:show).should have(1).item
    
    end
    
    it "should be garbage collectable" do
    
      def generate
        return WeakRef.new(Addressive::Network.new{
          node :bla do
            ref :blub
          end
        })
      end
      
      ref = generate()
      node = ref.node(:bla)
      node.should be_kind_of(Addressive::Node)
      
      GC.start
      
      ref.should_not be_weakref_alive
      node.should be_kind_of(Addressive::Node)
    
    end
  
  end
  
  describe Addressive::Node do
  
    it "should be exportable" do
    
      node_a = Addressive::Node.new
      node_a.uri_spec(:show) << {'pattern'=>'/arg_a/{arg_a}','public'=>true}
      
      node_b = Addressive::Node.new
      node_b.import( node_a.export )
      
      node_b.uri_spec(:show).should have(1).item
      node_b.uri_spec(:show).first.template.should == node_a.uri_spec(:show).first.template
      
    end
  
  end
  
  describe Addressive::URIBuilder do
  
    it "should be able to select a spec" do
      
      @nw = Addressive::Network.new do
      
        default 'type', 'default'
        
        node :frontend do
        
          uri :show, '/arg_a/{arg_a}', '/arg_b/{arg_b}'
        
        end
      
      end
      
      @nw[:frontend].uri(:show, {'arg_b'=>'b'}).to_s.should == '/arg_b/b'
      @nw[:frontend].uri(:show, {'arg_a'=>'a'}).to_s.should == '/arg_a/a'
      
    end
    
    it "should be able to add variables later" do
      
      node = Addressive::Node.new
      
      builder = Addressive::URIBuilder.new(node)
      
      builder.variables.should be_empty
      
      b2 = builder.uri({'x'=>'y'})
      
      builder.variables.should be_empty
      b2.variables.should == {'x'=>'y'}
      
    end
    
    it "should be able to traverse" do
      
      node = Addressive::Node.new
      node.edges[:sibling] = Addressive::Node.new
      
      builder = Addressive::URIBuilder.new(node)
      
      builder.variables.should be_empty
      
      b2 = builder.uri(:sibling, :something)
      b2.action.should == :something
      b2.node.should == node.edges[:sibling]
      
    end
  
  end
  
  describe Addressive::Router do
  
    class App
    
      def call(env)
      # This is not so rack-compatible.
      # But for testing, it's okay
        return [ @name, env['addressive'] ]
      end

      def generate_uri_specs(options)
        return {:show=> [options.fetch(:prefix,'') + '/show/{x}',options.fetch(:prefix,'') + '/{x}'],:new=> options.fetch(:prefix,'') + '/new' }
      end

      def to_app
        self
      end
      
      def initialize(name)
        @name = name
      end
      
    end
  
    it "should route" do
      
      nd = Addressive::Network.new{
      
        default 'type', 'default'
        
        node :frontend do
        
          app App.new('A'), :prefix => '/app_a'
          
          app App.new('B'), :prefix => '/app_b'
          
          ref :backend
        
        end
        
        node :backend do
        
          app App.new('C'), :prefix => '/backend'
          
          app App.new('D'), :prefix => '/backend/{y}'
        
        end
      
      }[:frontend]
      
      router = Addressive::Router.new
      router.add(nd)
      router.add(nd.edges[:backend])
      
      name, addressive = router.call({'PATH'=>'/app_a/show/3'})
      name.should == 'A'
      addressive.should be_kind_of(Hash)
      addressive[:node].should == nd
      addressive[:variables].should == {'x'=>'3'}
    
      name, addressive = router.call({'PATH'=>'/backend/show/5'})
      name.should == 'C'
      addressive[:node].should == nd.edges[:backend]
      addressive[:variables].should == {'x'=>'5'}
      
      name, addressive = router.call({'PATH'=>'/backend/new'})
      name.should == 'C'
      addressive[:node].should == nd.edges[:backend]
      addressive[:action].should == :new
      
      name, addressive = router.call({'PATH'=>'/backend/newz'})
      name.should == 'C'
      addressive[:node].should == nd.edges[:backend]
      addressive[:variables].should == {'x'=>'newz'}
      addressive[:action].should == :show
    
      name, addressive = router.call({'PATH'=>'/backend/do/5'})
      name.should == 'D'
      addressive[:node].should == nd.edges[:backend]
      addressive[:variables].should == {'y'=>'do','x'=>'5'}
      addressive[:action].should == :show
      
      name, addressive = router.call({'PATH'=>'/backend/do/new'})
      name.should == 'D'
      addressive[:node].should == nd.edges[:backend]
      addressive[:variables].should == {'y'=>'do'}
      addressive[:action].should == :new
    
    end
  
  end
  
  describe "docs" do
  
    gem 'yard'
    require 'yard'
    
    YARD.parse('lib/**/*.rb').inspect
    
    YARD::Registry.each do |object|
      if object.has_tag?('example')
        object.tags('example').each_with_index do |tag, i|
          code = tag.text.gsub(/(.*)\s*#=>(.*)(\n|$)/){
            "(#{$1}).should == #{$2}\n"
          }
          it "#{object.to_s} in #{object.file}:#{object.line} should have valid example #{(i+1).to_s}" do
            lambda{
              begin
                eval code
              rescue Exception => e
                puts e.backtrace.inspect
                raise
              end }.should_not raise_error
          end
        end
      end
    end
  
  end

end
