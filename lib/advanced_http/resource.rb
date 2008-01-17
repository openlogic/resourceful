require 'net/http'
require 'uri'
require 'net_http_auth_ext'
require 'benchmark'

require 'addressable/uri'

module AdvancedHttp
  class HttpRequestError < Exception
    attr_reader :response, :request
    
    def initialize(message, request, response)
      @response = response
      @request = request

      super(message)
    end

    def self.new_from(request, response, resource)
      msg = if request.method == 'GET'
              "#{resource.effective_uri} #{response.message} (#{response.code})"
            else
              "Received #{response.message} in response to #{request.method} #{resource.effective_uri} (#{response.code})"
            end
      
      case response.code
      when /^3/
        HttpRequestRedirected
      when /^4/
        HttpClientError
      when /^5/
        HttpServerError
      else
        HttpRequestError
      end.new(msg, request, response)
    end
  end
  
  class HttpClientError < HttpRequestError
  end
  
  class HttpServerError < HttpRequestError
  end

  class HttpRequestRedirected < HttpRequestError
  end

  # Interface for an object that can provide user names and passwords
  # for HTTP authentication.
  class AbstraceAuthenicationInfoProvider
    # Returns an array containing the account name and password
    # (+[account, password]+) to be used to authenticate at the
    # specified realm.  If no authentication information is known for
    # the specified realm +nil+ should be returned.
    def authentication_info(realm)
      raise NotImplementedError
    end
  end

  # A resource object represents a single resource on the World Wide
  # Web.  It is identified by one or more URIs and allows the normal
  # HTTP methods to be performed on the resource.
  class Resource
    attr_reader :uri
    
    # Initialize a newly created resource object.  Valid options:
    #
    #  +:logger+:: A Logger object tho which messages should be
    #     logged.  No logging is done unless this option is set.
    #     Errors are not logged but are raised.  If you want errors
    #     logged you must do it at the application level.
    #
    #  +:auth_info+:: An object which responds to
    #     +#authentication_info(realm)+ with an array, +[account,
    #     password]+ for that realm, or nil if the realm is not recognized.
    def initialize(uri, options = {})
      options = options.clone
      
      @logger = options.delete(:logger)
      @auth_info_provider = options.delete(:auth_info)
      
      raise ArgumentError, "Unknown option(s): #{options.keys.join(', ')}" unless options.empty?
      
      reset_uri(uri)
    end
    
    # Gets a representation of the resource this object represents and
    # returns the representation and associated meta-data (HTTP
    # headers, etc).  This method will follow redirect when
    # appropriate.  If the final response is not a 200 OK this method
    # will raise an exception.  If successful an HTTPResponse will be
    # returned.
    
    # Options 
    #
    #  +:accept+:: A MIME type, or array of MIME types, that are
    #    acceptable as the formats for the response.  Anything object
    #    that responds to +#to_str+ will work as a mime type.
    def get(options = {})
      request = Net::HTTP::Get.new(effective_uri.to_s)
      left_over_opts = configure_request_from_options(request, options)
      
      raise ArgumentError, "Unrecognized option(s): #{options.keys.join(', ')}" unless left_over_opts.empty?
      
      resp = do_request(request)
      
      return resp if /^2/ =~ resp.code # we are done
      
      # additional action is required
      if '301' == resp.code
        # response was a permanent redirect; follow it
        reset_uri(resp['location'])
        get
      elsif ['302','307'].include? resp.code
        # temporary redirect
        self.effective_uri = resp['location']
        get
      else
        # the response was unacceptable
        raise HttpRequestError.new_from(request, resp, self)
      end 
    end

    # Gets a representation of the resource this object represents.
    # This method will follow redirect when appropriate.  If the final
    # response is not a 200 OK this method will raise an exception.
    # If successful an HTTPResponse will be returned. 
    #
    # Options 
    #
    #  +:accept+:: A MIME type, or array of MIME types, that are
    #    acceptable as the formats for the response.  Anything object
    #    that responds to +#to_str+ will work as a mime type.
    #
    #  +:parse_as+:: Indicates that the return value should be the
    #    results of parsing the string representation.  The value of
    #    this option indicates what sort of parser should be used.
    #    Valid values are: +:json+.
    def get_body(options = {})
      options = options.dup
      parser = options.delete(:parse_as)
            
      body = get(options).body
      
      case parser
      when nil
        body
      when :json
        require 'json'
        JSON.parse(body)
      else        
        raise ArgumentError, "Unrecognized parser type #{parser}" unless parser.nil? or parser == :json
      end
    end
    
    # Deprecated.  Use `#get_body(:parse_as => :json)` instead.
    #
    # Returns the representation parses as a JSON document. 
    def get_json_body(options = {})
      get_body(options.merge(:parse_as => :json))
    end
        
    # Posts +data+ to this resource.  +mime_type+ is the MIME type of
    # +data+.  This method does *not* follow redirects, execpt for 303
    # See Other redirect.  In the case of a See Other response from
    # the post the redirection target will be gotten and that response
    # will be returned.
    #
    # Options 
    #
    #  +:accept+:: A MIME type, or array of MIME types, that are
    #    acceptable as the formats for the response.  Anything object
    #    that responds to +#to_str+ will work as a mime type.
    def post(data, mime_type, options = {})
      req = Net::HTTP::Post.new(effective_uri.to_s)
      req['content-type'] = mime_type
      left_over_opts = configure_request_from_options(req, options)
      raise ArgumentError, "Unrecognized option(s): #{options.keys.join(', ')}" unless left_over_opts.empty?
      resp = do_request(req, data)

      return resp if /^2/ === resp.code
      
      if '303' == resp.code
        alt_resource = Resource.new(resp['location'])
        alt_resource.get_response
      else
        # something went wrong...
        raise HttpRequestError.new_from(req, resp, self)
      end
    end

    # Puts +data+ to this resource.  +mime_type+ is the MIME type of
    # +data+.  This method does *not* follow redirects.  An Exception
    # will raised for any non-2xx response.
    #
    # Options 
    #
    #  +:accept+:: A MIME type, or array of MIME types, that are
    #    acceptable as the formats for the response.  Anything object
    #    that responds to +#to_str+ will work as a mime type.
    def put(data, mime_type, options = {})
      req = Net::HTTP::Put.new(effective_uri.to_s)
      req['content-type'] = mime_type
      left_over_opts = configure_request_from_options(req, options)
      raise ArgumentError, "Unrecognized option(s): #{options.keys.join(', ')}" unless left_over_opts.empty?
      
      resp = do_request(req, data)

      return resp if /^2/ === resp.code
      
      # something went wrong...
      raise HttpRequestError.new_from(req, resp, self)
    end

    # Returns the current effective URI for this resource.  The
    # effective URI is either the URI specified when the resource was
    # created or the one reached by following one or more redirects.
    def effective_uri
      @effective_uri || @uri
    end
    

    # Clears all transient information about this resource.  For
    # example, this will cause the next call to get to fetch the URI
    # for this resource, rather than the effective URI.
    def reset
      self.effective_uri = nil
    end
    
    protected

    attr_reader :logger, :auth_info_provider
    
    # levels: :info, :debug.
    def log(level, message)
      return unless logger

      case level
      when :info
        logger.info(message)
      when :debug
        logger.debug(message)
      end
        
    end
    
    # Sets the effective URI for this resource.
    def effective_uri=(new_effective_uri)
      @effective_uri = new_effective_uri.nil? ? nil : Addressable::URI.parse(new_effective_uri)
    end
      
    def reset_uri(new_uri)
      @effective_uri = nil
      @uri = Addressable::URI.parse(new_uri)
    end
    
    # makes an HTTP request against the server that hosts this resource and returns the HTTPResponse.
    def do_request(an_http_request, body = nil)
      Net::HTTP.start(effective_uri.host, effective_uri.port) do |c|
        
        resp = nil
        bm = Benchmark.measure do 
          resp = c.request(an_http_request, body)
        end
        log(:info, "  #{an_http_request.method} #{effective_uri} (#{resp.code}) (#{format('%0.3f', bm.real)} sec)")
        
        if '401' == resp.code          
          #unless creds = auth_info(resp.realm)
          unless creds = auth_info(resp.realm)
            log(:warn, "    No credentials known for #{resp.realm}")
            return resp
          end
          # Retry with authorization 
          account, password = creds
          if resp.digest_auth_allowed?
            auth_type = 'digest'
            an_http_request.digest_auth(account, password, resp.digest_challenge)
          elsif resp.basic_auth_allowed?
            auth_type = 'basic'
            an_http_request.basic_auth(account, password)
          else
            return resp  # don't know what to do...
          end
          bm = Benchmark.measure do 
            resp = c.request(an_http_request)
          end
          log(:info, "  #{an_http_request.method} #{effective_uri} (#{an_http_request.authentication_scheme.downcase}_auth: realm='#{an_http_request.authentication_realm}', account='#{creds.first}') (#{resp.code}) (#{format('%0.3f', bm.real)} sec)")
        end 
         
        resp
        
      end
      
    rescue => e
      log(:debug, "  #{an_http_request.method} #{effective_uri} failed with #{e.message}")
      raise e.class, e.message + " (while #{an_http_request.method} #{effective_uri})"
    end

    def auth_info(realm)
      auth_info_provider ? auth_info_provider.authentication_info(realm) : nil
    end
    
    def configure_request_from_options(request, options)
      options = options.clone
      
      if accept = options.delete(:accept)
        request['accept'] = [accept].flatten.map{|m| m.to_str}
      end
      
      return options
    end
  end
end

  
