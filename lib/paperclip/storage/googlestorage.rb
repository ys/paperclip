# Amazon's S3 file hosting service is a scalable, easy place to store files for
   # distribution. You can find out more about it at http://aws.amazon.com/s3
   # There are a few S3-specific options for has_attached_file:
   # * +googe_credentials+: Takes a path, a File, or a Hash. The path (or File) must point
   #   to a YAML file containing the +access_key_id+ and +secret_access_key+ that Google
   #   gives you. You can 'environment-space' this just like you do to your
   #   database.yml file, so different environments can use different accounts:
   #     development:
   #       access_key_id: 123...
   #       secret_access_key: 123...
   #     test:
   #       access_key_id: abc...
   #       secret_access_key: abc...
   #     production:
   #       access_key_id: 456...
   #       secret_access_key: 456...
   #   This is not required, however, and the file may simply look like this:
   #     access_key_id: 456...
   #     secret_access_key: 456...
   #   In which case, those access keys will be used in all environments. You can also
   #   put your bucket name in this file, instead of adding it to the code directly.
   #   This is useful when you want the same account but a different bucket for
   #   development versus production.
   # * +google_storage_permissions+: This is a String that should be one of the access
   #   policies that Google provides (more information can be found here:
   #   http://code.google.com/apis/storage/docs/developer-guide.html#authorization
   #   The default for Paperclip is :public_read.
   # * +google_storage_protocol+: The protocol for the URLs generated to your Google assets. Can be either
   #   'http' or 'https'. Defaults to 'http' when your :google_storage_permissions are :public_read (the
   #   default), and 'https' when your :google_storage_permissions are anything else.
   # * +google_storage_headers+: TODO - Add support and docs for headers, may already work but untested
   # * +bucket+: This is the name of the Google bucket that will store your files. 
   #   You can define the bucket as a Proc if you want to determine it's name at runtime.
   #   Paperclip will call that Proc with attachment as the only argument.
   # * +url+: TODO
   # * +path+: TODO
   module Googlestorage
     def self.extended base
       begin
         require 'gstore'
       rescue LoadError => e
         e.message << " (You may need to install the google_storage gem)"
         raise e
       end
       base.instance_eval do
         @google_storage_credentials = parse_credentials(@options[:google_storage_credentials])
         @bucket             = @options[:bucket]
         @google_storage_options     = @options[:google_storage_options]     || {}
         @google_storage_permissions = @options[:google_storage_permissions] || :public_read
         @google_storage_protocol    = @options[:google_storage_protocol]    || (@google_storage_permissions == :public_read ? 'http' : 'https')
         @google_storage_headers     = @options[:google_storage_headers]     || {}
         @google_storage_host_alias  = @options[:google_storage_host_alias]
         @url            = ":google_storage_path_url" # Add Google url here: unless @url.to_s.match(/^:s3.*url$/)
         
         @client = GStore::Client.new(
           :access_key => @google_storage_credentials['access_key_id'],
           :secret_key => @google_storage_credentials['secret_access_key']
           )
         
       end
       Paperclip.interpolates(:google_storage_path_url) do |attachment, style|
         "#{attachment.google_storage_protocol}://commondatastorage.googleapis.com/#{attachment.bucket_name}/#{attachment.path(style).gsub(%r{^/}, "")}"
       end
       
     end
     
     def bucket_name
       @bucket
     end
     
     def google_storage_protocol
       @google_storage_protocol
     end
 
     def exists?(style = default_style)
       @client.get_object(@bucket, style)
     end
 
     def to_file style = default_style
       return @queued_for_write[style] if @queued_for_write[style]
       file = Tempfile.new(path(style))
       file.write((path(style)))
       file.rewind
       return file
     end
 
     def flush_writes #:nodoc:
       @queued_for_write.each do |style, file|
         # begin
           log("saving #{path(style)}")
           @client.put_object(@bucket, path(style), :data => file.read, :headers => {:x_goog_acl => @google_storage_permissions})
         # rescue 
         #   raise
         # end
       end
       @queued_for_write = {}
     end
 
     def flush_deletes #:nodoc:
       @queued_for_delete.each do |path|
         # begin
           log("deleting #{path}")
           @client.delete_object(@bucket, path)
         # rescue AWS::S3::ResponseError
         #   # Ignore this.
         # end
       end
       @queued_for_delete = []
     end
     
     def parse_credentials creds
       creds = find_credentials(creds).stringify_keys
       (creds[Rails.env] || creds).symbolize_keys
       creds
     end
     
     def find_credentials creds
       puts creds.class
       case creds
       when File
         YAML::load(ERB.new(File.read(creds.path)).result)
       when String, Pathname
         YAML::load(ERB.new(File.read(creds)).result)
       when Hash
         creds
       else
         raise ArgumentError, "Credentials are not a path, file, or hash."
       end
     end
     private :find_credentials
   end