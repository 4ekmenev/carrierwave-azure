# Adapted from the SharedAccessSignature class found in the Azure
# Extensions project by David Michael located at https://github.com/dmichael/azure-contrib

require 'azure'
require 'hashie/dash'
require 'addressable/uri'

module Azure
  module Core
    module Auth
      class SharedAccessSignature
        class Version20130815 < Hashie::Dash
          property :protocol,    default: 'https'
          property :resource,    default: 'c', required: true
          property :permissions, default: 'r', required: true
          property :start,       default: ''
          property :identifier,  default: ''
          property :expiry, required: true
          property :canonicalized_resource, required: true
          # Do not change this
          property :version, default: '2013-08-15'
        end

        attr_accessor :uri, :options

        def initialize(uri, options = {}, account =  ENV['AZURE_STORAGE_ACCOUNT'])
          # This is the uri that we are signing
          @uri = Addressable::URI.parse(uri)

          is_blob = options[:resource] == 'b'

          account ||= ::Azure.config.send('storage_account_name')

          # Create the options hash that will be turned into a query string
          @options = Version20130815.new(options.merge(canonicalized_resource: canonicalized_resource(@uri, account, is_blob)))
        end

        # Create a "canonicalized resource" from the full uri to be signed
        def canonicalized_resource(uri, account = ENV['AZURE_STORAGE_ACCOUNT'], is_blob = false)
          path = uri.path # Addressable::URI
          # There is only really one level deep for containers, the remainder is the BLOB key (that looks like a path)
          path_array = path.split('/').reject {|p| p == ''}
          container = path_array.shift
          account ||= ::Azure.config.send('storage_account_name')

          string = if is_blob
                     File.join('/', account, container, path_array.join('/'))
                   else
                    File.join('/', account, container)
                   end
          string
        end

        # When creating the query string from the options, we only include the no-empty fields
        # - this is opposed to the string that gets signed which includes them as blank.
        def create_query_values(options = Version20130815.new)
          # Parts
          parts       = {}
          parts[:st]  = URI.unescape(options[:start]) unless options[:start] == ''
          parts[:se]  = URI.unescape(options[:expiry])
          parts[:sr]  = URI.unescape(options[:resource])
          parts[:sp]  = URI.unescape(options[:permissions])
          parts[:si]  = URI.unescape(options[:identifier]) unless options[:identifier] == ''
          parts[:sig] = URI.unescape( create_signature(options) )

          parts
        end

        def create_signature(options = Version20130815)
          string_to_sign  = []
          %i(permissions start expiry canonicalized_resource identifier).each do |key|
            string_to_sign << options[key] if options.has_key?(key)
          end

          secret_key = ENV['AZURE_STORAGE_ACCESS_KEY'].presence || ::Azure.config.send('storage_access_key')

          ::Azure::Core::Auth::Signer.new(secret_key)
                                     .sign(string_to_sign.join("\n")
                                     .force_encoding("UTF-8"))
        end

        def sign
          @uri.query_values = (@uri.query_values || {}).merge(create_query_values(@options))
          @uri.to_s
        end
      end
    end
  end
end
