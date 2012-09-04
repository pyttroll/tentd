require 'securerandom'

module TentD
  module Model
    class Post
      include DataMapper::Resource
      include Permissible
      include RandomPublicId

      storage_names[:default] = "posts"

      property :id, Serial
      property :entity, String
      property :public, Boolean, :default => false
      property :type, String
      property :licenses, Array
      property :content, Json
      property :published_at, DateTime, :default => lambda { |*args| Time.now }
      property :received_at, DateTime, :default => lambda { |*args| Time.now }
      property :updated_at, DateTime
      property :app_name, String
      property :app_url, String
      property :original, Boolean, :default => false
      property :known_entity, Boolean

      has n, :permissions, 'TentD::Model::Permission', :constraint => :destroy
      has n, :attachments, 'TentD::Model::PostAttachment', :constraint => :destroy
      belongs_to :app, 'TentD::Model::App', :required => false

      def self.fetch_with_permissions(params, current_auth)
        super do |params, query, query_bindings|
          if params.since_time
            query << "AND posts.published_at > ?"
            query_bindings << Time.at(params.since_time.to_i)
          end

          if params.before_time
            query << "AND posts.published_at < ?"
            query_bindings << Time.at(params.before_time.to_i)
          end

          if params.post_types
            params.post_types = params.post_types.split(',').map { |url| URI.unescape(url) }
            if params.post_types.any?
              query << "AND posts.type IN ?"
              query_bindings << params.post_types
            end
          end
        end
      end

      def self.public_attributes
        [:known_entity, :app_name, :app_url, :entity, :type, :licenses, :content, :published_at, :original]
      end

      def can_notify?(app_or_follower)
        return true if public
        case app_or_follower
        when AppAuthorization
          app_or_follower.scopes && app_or_follower.scopes.include?(:read_posts) ||
          app_or_follower.post_types && app_or_follower.post_types.include?(type)
        when Follower
          return false unless original
          (permissions.all(:group_public_id => app_or_follower.groups) +
           permissions.all(:follower_access_id => app_or_follower.id)).any?
        end
      end

      def as_json(options = {})
        attributes = super(:only => [:entity, :type, :licenses, :content, :published_at])
        attributes[:id] = public_id
        attributes[:app] = { :url => app_url, :name => app_name }
        attributes[:attachments] = attachments.all.map { |a| a.as_json }
        attributes[:permissions] = { :public => public }

        if options[:kind] == :app
          attributes[:received_at] = received_at
          attributes[:known_entity] = known_entity
        end

        if options[:permissions]
          groups = []
          entities = []
          permissions.each do |permission|
            groups << permission.group.public_id if permission.group
            entities << permission.follower.entity if permission.follower
          end
          attributes[:permissions][:groups] = groups.uniq
          attributes[:permissions][:entities] = Hash[entities.uniq.map { |e| [e, true] }]
        end

        Array(options[:exclude]).each { |k| attributes.delete(k) if k }
        attributes
      end
    end
  end
end