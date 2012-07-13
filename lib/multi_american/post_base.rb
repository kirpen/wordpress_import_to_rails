module WP
  class PostBase < Node
    SCPR_CLASS = "BlogEntry"
    
    DEFAULTS = {
      blog_id: MultiAmerican::BLOG_ID,
      blog_slug: MultiAmerican::BLOG_SLUG,
      author_id: MultiAmerican::AUTHOR_ID,
      is_published: 0,
      blog_asset_scheme: "",
      comment_count: 0
    }
    
    XML_AR_MAP = {
      id:                 :wp_id,
      post_name:          :slug,
      title:              :title,
      content:            :content,
      pubDate:            :published_at,
      status:             :status,
      excerpt:            :_teaser
    }
    
    administrate  
    self.list_fields = [
      ['id', title: "WP-ID"],
      ['post_type'],
      ['title', link: true, display_helper: :display_or_fallback],
      ['post_name', title: "Slug"],
      ['pubDate'],
      ['status']
    ]

    # -------------------
    # Class
    
    class << self
      # -------------------      
      # Node rejectors
      
      def invalid_child(node)
        %w{comment}.include?(node.name) || 
        (Builder.is_postmeta(node) and node.at_xpath("./wp:meta_value").content == "{{unknown}}" ) ||
        super
      end
      
      def invalid_item(node)
        # Only published content
        node.at_xpath("./wp:status").content != "publish"
      end
      
      # -------------------      
      
      def nested_attributes
        [:@categories, :@postmeta]
      end
    end
    

    # -------------------
    # Instance
    
    def initialize(element)
      @builder = { categories: [], postmeta: [] }
      super(element)
    end
    
    def sorter
      Time.parse(self.pubDate)
    end

    
    # -------------------
    # Builder for class-specific attributes
    def build_extra_attributes(object, object_builder)
      # Merge in existing author_id if user exists
      # Otherwise it will just use Leslie's ID
      if existing_user = AdminUser.where(username: self.dc).first
        object_builder[:author_id] = Bio.where(user_id: existing_user.id).first.id
      end

      # -------------------
      # Merge in Tags and Categories
      associations = [
        { name: :tags, class_name: "WP::Tag", records: self.categories.select { |c| c[:domain] == "post_tag" } },
        { name: :blog_categories, class_name: "WP::Category", records: self.categories.select { |c| c[:domain] == "category" } }
      ]

      associations.each do |assoc|
        assoc[:records].each do |stored_object|
          # Stored object is what gets stored with the post
          # It's a hash and just gives us the title and the slug
          
          # Tags and categories should all be in the cache
          # at this point.
          # xml_object should return a real object from cache.
          # eg., WP::Tag or WP::Category
          xml_object = assoc[:class_name].constantize.find.find do |real_obj| 
            real_obj.send(assoc[:class_name].constantize.raw_real_map.first[1]) == stored_object[assoc[:class_name].constantize.raw_real_map.first[0]]
          end

          # If ar_record is present, use it. If not, import the tag.
          if xml_object.ar_record.present?
            assoc_obj = xml_object.ar_record
          else
            assoc_obj = xml_object.import
          end
          
          # Add the association object to the builder
          object.send(assoc[:name]).push assoc_obj
        end
      end
      
      # -------------------
      # Get the embeds, and insert them into body if referenced
      # Note that the video won't necessarily be referenced in the body,
      # in which case gsub! won't do anything (return nil)
      self.postmeta.select { |pm| pm[:meta_key] =~ /_oembed/ }.each do |pm|
        if (match = pm[:meta_value].match(/youtube\.com\/(?:.+?\/)?(?<vid>[\w-]+)/))
          # Got a YouTube embed
          object_builder[:content].gsub!(/^http.+?youtube.+?#{match[:vid]}.*$/, pm[:meta_value])
        
        elsif (match = pm[:meta_value].match(/vimeo\.com\/video\/(?<vid>\d+)/))
          # Got a vimeo iframe
          object_builder[:content].gsub!(/^http.+?vimeo.+?#{match[:vid]}.*$/, pm[:meta_value])
          
        elsif (match = pm[:meta_value].match(/vimeo\.com\/moogaloop.+?clip_id=(?<vid>\d+)/))
          # Got old-style vimeo embed
          object_builder[:content].gsub!(/^http.+?vimeo.+?#{match[:vid]}.*$/, pm[:meta_value])
        end
      end
      
      
      # -------------------
      # Change the [caption] tags into the standard HTML
      self.content.gsub!(/\[caption(.+?)\](.+?)\[\/caption\]/) do |match|
        properties = {}
        $1.split("\"").each_slice(2) { |pair| properties[pair[0].lstrip.chomp("=").to_sym] = pair[1] }
        
        view = ActionView::Base.new(ActionController::Base.view_paths, {})        
        view.render("/admin/multi_american/attachment", properties: properties, content: $2)
      end
      
      
      # -------------------
      # Merge in Disqus thread ID (or nil)
      if dsq_meta = self.postmeta.find { |p| p[:meta_key] == "dsq_thread_id" }
        object.dsq_thread_id = dsq_meta[:meta_value]
      end
      
      return [object, object_builder]
    end


    # -------------------
    # Convenience Methods
    
    def to_title
      title
    end
    
    def id
      post_id.to_i
    end
    
    def status=(value)
      status_map = {
        "publish" => 5,
        "inherit" => 5,
        "draft"   => 0
      }
      
      @status = status_map[value]
    end
  end
end