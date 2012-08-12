require 'addressive'
require 'weakref'
require 'stringio'
require 'rack/mock'

describe Addressive do

  describe 'graph' do
  
    before(:each){
    
      @nw = Addressive.graph do
        node(:frontend){
          ref :backend
          ref :remote
        }
        node(:backend){
          ref :frontend
        }
        node(:remote){
        }
      end
    
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
        return WeakRef.new(Addressive.graph{
          node :bla do
            ref :blub
          end
        })
      end
      
      ref = generate()
      node = ref.node(:bla)
      node.should be_kind_of(Addressive::Node)
      
      GC.start
      
      ref.weakref_alive?.should_not be_true
      node.should be_kind_of(Addressive::Node)
    
    end
  
  end
  
  describe Addressive::URIBuilder do
  
    before(:each) do
    
      @nw = Addressive.graph do
      
        default 'type', 'default'
        
        node :frontend do
        
          uri :show, '/arg_a/{arg_a}', '/arg_b/{arg_b}'
        
        end
      
      end
    
    end
  
    it "should be able to select a spec" do
      
      
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
    
    it "should work with models" do
    
      o = Object.new
      def o.to_addressive
        return [:show, {'arg_a'=>'foo'}]
      end

      @nw[:frontend].uri(o).to_s.should ==  '/arg_a/foo'
    
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
    
    it "should raise, when no route was found" do
    
      lambda{ @nw[:frontend].uri(:boo).to_s }.should raise_error( Addressive::Error )
      lambda{ @nw[:frontend].uri(:bcknd, :show).to_s }.should raise_error( Addressive::Error )
    
    end
  
  end
  
  describe Addressive::Router do
  
    class App
    
      def call(env)
      # This is not so rack-compatible.
      # But for testing, it's okay
        return [ 200, {}, [@name + ' - ' + env['addressive'].action.to_s] ]
      end

      def generate_uri_specs(builder)
      
        builder.uri :show, '/show/{x}', '/{x}'
      
        builder.uri :new, '/new'

        builder.uri '/'
      
      end

      def to_app
        self
      end
      
      def initialize(name)
        @name = name
      end
      
    end
  
    it "should route" do
      
      nd = Addressive.graph{
      
        default 'type', 'default'
        
        node :frontend do
        
          app App.new('A'), :prefix => '{proto}://{host}/app_a'
          
          app App.new('B'), :prefix => '{proto}://{host}/app_b'
          
          ref :backend
        
        end
        
        node :backend do
        
          app App.new('C'), :prefix => '{proto}://{host}/backend'
          
          app App.new('D'), :prefix => '{proto}://{host}/backend/{y}'
        
        end
      
      }[:frontend]
      
      router = Addressive::Router.new
      
      router.add(nd)
      router.add(nd.edges[:backend])
      
      app = Rack::MockRequest.new(router)
      
      app.get('http://www.example.com/app_a/show/3').body.should == 'A - show'

      app.get('http://www.example.com/app_a/').body.should == 'A - default'

      app.get('http://www.example.com/backend/show/5').body.should == 'C - show'
      
      app.get('http://www.example.com/backend/new').body.should == 'C - new'
      
      app.get('http://www.example.com/backend/newz').body.should == 'C - show'
      
      app.get('http://www.example.com/backend/do/5').body.should == 'D - show'
      
      app.get('http://www.example.com/backend/do/new').body.should == 'D - new'
      
    end

    it "should work if two routes are somewhat similiar" do

      received_args = []

      node = Addressive.node do

        default :app, lambda{|env| received_args << env['addressive'].variables ; [404,{},[""]]}

        uri '/object/{id}'

        uri '/object/{?query*}'

      end

      router = Addressive::Router.new

      router.add( node )

      app = Rack::MockRequest.new(router)

      app.get('/object/?foo.bar=baz')

      received_args.should == [{'query' => {'foo.bar'=>'baz'}}]

    end
    
    it "should only extract as many as necessary" do
    
      r = Addressive::Router.new
      n = Addressive.node do
      
        default :app, lambda{|env| [200,{},[]] }
      
        uri :foo ,'{foo}'
        uri :bar ,'{foo}'
        uri :baz ,'{foo}'
        
      end
      
      r.add(n)
      
      r.seal!
      
      r.routes[0].template.should_receive(:extract).exactly(1).times.and_return({'foo'=>'xxx'})
      r.routes[1].template.should_not_receive(:extract)
      r.routes[2].template.should_not_receive(:extract)
      
      result = Rack::MockRequest.new(r).get('http://foo.bar/xxx')
      result.status.should == 200
    
    end
    
    it "should work with substring trees" do
    
    
      r = Addressive::Router.new(
        Addressive::Router::Tree::SubstringSplit.new('/bar/',
          Addressive::Router::Tree::Direct.new,
          Addressive::Router::Tree::Direct.new )
        )
      n = Addressive.node do
      
        default :app, lambda{|env| [200,{},[]] }
      
        uri :foo ,'/bar/{bar}'
        uri :bar ,'/{bar}'
        uri :baz ,'/b{ar}'
        
      end
      
      r.add(n)
      
      r.seal!
      
      r.routes[0].template.should_not_receive(:extract)
      r.routes[1].template.should_not_receive(:extract)
      r.routes[2].template.should_receive(:extract).exactly(1).times.and_return({'ar'=>'xx'})
      
      result = Rack::MockRequest.new(r).get('http://foo.bar/bxx')
    
    end
    
    it "should work with prefix trees" do
    
    
      r = Addressive::Router.new(
        Addressive::Router::Tree::PrefixSplit.new('/bar/',
          Addressive::Router::Tree::Direct.new,
          Addressive::Router::Tree::Direct.new )
        )
      n = Addressive.node do
      
        default :app, lambda{|env| [200,{},[]] }
      
        uri :foo ,'/bar/{bar}'
        uri :bar ,'/{bar}'
        uri :baz ,'/x{oo}'
        
      end
      
      r.add(n)
      
      r.seal!
      
      r.routes[0].template.should_not_receive(:extract)
      r.routes[1].template.should_not_receive(:extract)
      r.routes[2].template.should_receive(:extract).exactly(1).times.and_return({'oo'=>'xxx'})
      
      result = Rack::MockRequest.new(r).get('http://foo.bar/xxx')
    
    end
  
  end
  
  describe Addressive::Static do
  
    before(:each) do
    
      @main = Addressive.graph{
      
        node :main do
        
          app Addressive::Static.new(:root=>File.dirname(__FILE__))
          
          edge :foo do
          
            app Addressive::Static.new(:root=>File.join(File.dirname(__FILE__),'bar')), :prefix=>'/foo'
          
          end
          
          edge :bar do
          
            app Addressive::Static.new(:root=>File.join(File.dirname(__FILE__),'bar')), :prefix=>'http://static.example.com/'
          
          end
          
        end
      
      }[:main]
    
    end
  
    it "should live happily on a node" do
      
      @main.uri(:get,'file'=>'afile.ext').to_s.should == '/afile.ext'
      
      @main.uri(:foo, :get,'file'=>'afile.ext').to_s.should == '/foo/afile.ext'
    
    end
    
    it "should serve the desired files" do
    
      router = Addressive::Router.new
      router.add @main
      router.add @main.edges[:foo]
      router.add @main.edges[:bar]
      
      mock = Rack::MockRequest.new(router)
      
      f1 = mock.get('http://foo.bar/foo/afile.ext')
      f1.status.should == 200
      f1.body.should == "A\n"
      
      f2 = mock.get('http://foo.bar/afile.ext')
      f2.status.should == 200
      f2.body.should == "B\n"
      
      f3 = mock.get('http://static.example.com/afile.ext')
      f3.status.should == 200
      f3.body.should == "A\n"
    
    end
    
    it "should kill traversals" do
    
      router = Addressive::Router.new
      router.add @main
      router.add @main.edges[:foo]
      router.add @main.edges[:bar]
      
      str = ''
      sio = StringIO.new(str)
      
      f1 = Rack::MockRequest.new(router).get( 'http://foo.bar/foo/../afile.ext' )
      f1.status.should >= 400
      
      f1 = Rack::MockRequest.new(router).get( 'http://foo.bar/foo/%2e%2e/afile.ext' )
      f1.status.should >= 400
    
    end
    
    it "should work with routers" do
      
      router = Addressive::Router.new
      router.add @main
      router.add @main.edges[:foo]
      
      router.routes_for('/afile.ext','http://foo.bar/afile.ext').should have(1).item
      
      router.routes_for('/afile.ext','http://foo.bar/afile.ext').first.variables['file'].should == 'afile.ext'
      
      router.routes_for('/foo/afile.ext','http://foo.bar/foo/afile.ext').should have(2).items
      
      router.routes_for('/foo/afile.ext','http://foo.bar/foo/afile.ext').first.variables['file'].should == 'afile.ext'
      
    end
  
  end


  describe "backports" do

    it "should not use the backports on 1.9.3", :if => (RUBY_VERSION > "1.9") do
      [].method(:collect_concat).source_location.should be_nil
    end

  end

  describe "docs" do
  
    gem 'yard'
    require 'yard'
    
    YARD.parse('lib/**/*.rb').inspect
    
    YARD::Registry.each do |object|
      if object.has_tag?('example')
        object.tags('example').each_with_index do |tag, i|
          code = tag.text.gsub(/(.*)\s*#([=!])>(.*)(\n|$)/){
            if $2 == '='
              "(#{$1}).should == #{$3}\n"
            elsif $2 == '!'
              "lambda{(#{$1})}.should raise_error(#{$3})\n"
            end
          }
          it "#{object.to_s} in #{object.file}:#{object.line} should have valid example #{(i+1).to_s}" do
            lambda{eval code}.should_not raise_error
          end
        end
      end
    end
  
  end

end
