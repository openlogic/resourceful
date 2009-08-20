require File.dirname(__FILE__) + "/../spec_helper.rb"


describe Resourceful::Header do 
  def self.should_support_header(name)
    const_name = name.upcase.gsub('-', '_')
    meth_name  = name.downcase.gsub('-', '_')

    eval <<-RUBY
      it "should have constant `#{const_name}` for header `#{name}`" do 
        Resourceful::Header::#{const_name}.should == '#{name}'
      end

      it "should have accessor method `#{meth_name}` for header `#{name}`" do 
        Resourceful::Header.instance_methods.should include(:#{meth_name})
      end

    RUBY
  end

  should_support_header('Accept')
  should_support_header('Accept-Charset')
  should_support_header('Accept-Encoding')
  should_support_header('Accept-Language')
  should_support_header('Accept-Ranges')
  should_support_header('Age')
  should_support_header('Allow')
  should_support_header('Authorization')
  should_support_header('Cache-Control')
  should_support_header('Connection')
  should_support_header('Content-Encoding')
  should_support_header('Content-Language')
  should_support_header('Content-Length')
  should_support_header('Content-Location')
  should_support_header('Content-MD5')
  should_support_header('Content-Range')
  should_support_header('Content-Type')
  should_support_header('Date')
  should_support_header('ETag')
  should_support_header('Expect')
  should_support_header('Expires')
  should_support_header('From')
  should_support_header('Host')
  should_support_header('If-Match')
  should_support_header('If-Modified-Since')
  should_support_header('If-None-Match')
  should_support_header('If-Range')
  should_support_header('If-Unmodified-Since')
  should_support_header('Keep-Alive')
  should_support_header('Last-Modified')
  should_support_header('Location')
  should_support_header('Max-Forwards')
  should_support_header('Pragma')
  should_support_header('Proxy-Authenticate')
  should_support_header('Proxy-Authorization')
  should_support_header('Range')
  should_support_header('Referer')
  should_support_header('Retry-After')
  should_support_header('Server')
  should_support_header('TE')
  should_support_header('Trailer')
  should_support_header('Transfer-Encoding')
  should_support_header('Upgrade')
  should_support_header('User-Agent')
  should_support_header('Vary')
  should_support_header('Via')
  should_support_header('Warning')
  should_support_header('WWW-Authenticate')

  

end