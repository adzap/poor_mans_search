require 'mirror'

module YFactorial
  module PoorMansSearch
    
    # Get access to the junk
    def self.included(base)
      base.extend(ClassMethods) 
    end
    
    module ClassMethods
      
      # Make this model sql searchable on the given columns
      #
      #   class Post < ActiveRecord::Base
      #     poor_mans_search_on :title, :body, :author, :category
      #   end
      #
      # Then, use the <tt>search_for</tt> class method to perform a search against
      # a collection of keywords for each field that has been marked as being
      # searchable.  Performs a SQL query text search on the searchable columns
      # using <tt>lower(col) like '%keyword%'"</tt> conditions.
      #
      #   Post.search_for('keyword1','keyword2')
      #
      # Can also pass in options hash, supports all options supported by standard
      # <tt>ActiveRecord::Base.find</tt> method.
      #
      #   Post.search_for('keyword1', keyword2, :conditions => ["active = ?", true], :order => 'created_at DESC')
      #
      # If you just want to get the search sql without calling find (useful when using pagination and other
      # non-standard finders) you can access <tt>build_search_sql_for</tt>
      #
      #   Post.paginate(:all, :conditions => Post.build_search_sql_for('keyword1', 'keyword2'))
      #
      def poor_mans_search_on(*fields)
        
        # Store the searchable fields and their options
        write_inheritable_attribute(:sql_searchable_options, fields.last.is_a?(::Hash) ? fields.pop : {})
        write_inheritable_attribute(:sql_searchable_fields, fields.flatten)
        [:sql_searchable_fields, :sql_searchable_options].each {|attr| class_inheritable_reader attr }
        
        # Include search methods and helper reflection library
        include YFactorial::Mirror::Associations
        extend YFactorial::PoorMansSearch::SingletonMethods
        
      end
    end
    
    module SingletonMethods
      
      # Search for all items whose searchable fields contain the given keywords
      def search_for(*keywords)
        
        # Parse out options hash (if on Edge, could've used keywords.extract_options!)
        options = keywords.last.is_a?(::Hash) ? keywords.pop : {}
        
        # Build uber conditions
        all_conditions = merged_conditions(build_sql_search_conditions_for(keywords), options.delete(:conditions))
        
        # Send off to normal finder with options and uber-conditions
        find(:all, options.merge(:conditions => all_conditions))
      end

      # Get the SQL conditional statement that satisfies this search query
      #
      # Useful when need to craft your own sql statements but still want search functionality.
      #
      #   Post.paginate(:all, :conditions => Post.build_sql_search_conditions_for('keyword1', 'keyword2'))
      #
      def build_sql_search_conditions_for(*keywords)
        
        # Get the search query on this model for the keywords
        search_query = sql_searchable_fields.collect do |col|
          keywords.flatten.collect do |keyword|
            sanitize_sql_array(["lower(#{table_name}.#{col}) like '%s'", "%#{keyword.downcase}%"])
          end.join(" OR ")
        end.join(" OR ")
        
        # Get the search query for included models to search on
        ids_sql = build_ids_for_matching_included_models_sql(keywords)
        includes_query = "#{self.table_name}.#{self.primary_key} in (#{ids_sql})" if not ids_sql.blank?
        
        # Combine them for the mother-query
        includes_query ? "(#{search_query}) OR (#{includes_query})" : "#{search_query}"
      end
      
      
      
      # Build the SQL statement that will get the ids of all models whose associated models match
      # the given search keywords.
      #
      #   class Article < ActiveRecord::Base
      #     sql_searchable_on :title, :body, :search_associated => [:comments, :tags]
      #     has_many :comments
      #     has_and_belongs_to_many :tags, :through => :taggings
      #   end
      #
      #   class Comment < ActiveRecord::Base
      #     sql_searchable_on :body
      #   end
      #
      #   class Tag < ActiveRecord::Base
      #     sql_searchable_on :name
      #   end
      #
      #   Article.build_ids_for_matching_included_models_sql(['keyword1'], :comments)
      #     #=> "SELECT comments.article_id FROM comments WHERE (...) UNION \
      #{         SELECT taggings.article_id FROM taggings WHERE (...)"
      #
      def build_ids_for_matching_included_models_sql(keywords)
        (sql_searchable_options[:search_associated] || []).collect do |include_model|
          build_ids_for_matching_included_model_sql(keywords, include_model)
        end.join(" UNION ")
      end
      
      
      # Build the SQL statement that will get the ids of all models whose given associated model
      # matches the given search keywords.
      #
      #   class Article < ActiveRecord::Base
      #     sql_searchable_on :title, :body, :search_associated => [:comments]
      #     has_many :comments
      #   end
      #
      #   class Comment < ActiveRecord::Base
      #     sql_searchable_on :body
      #   end
      #
      #   Article.build_ids_for_matching_included_model_sql(['keyword1'], :comments)
      #     #=> "SELECT comments.article_id FROM comments \
      #            WHERE id in \
      #           (SELECT comments.id FROM comments WHERE (lower(comments.body) like '%keyword1%'))"
      #
      def build_ids_for_matching_included_model_sql(keywords, include_model)
        
        ass_reflection = self.mirror.association[include_model]

        "SELECT #{ass_reflection.queryable_table}.#{ass_reflection.source_id_column} FROM \
         #{ass_reflection.queryable_table} WHERE \
         (#{ass_reflection.queryable_table}.#{ass_reflection.target_id_column} in (#{build_matching_included_model_ids_sql(ass_reflection, keywords)}))"
      end
      
      # Build the SQL statement that will get the ids of all associated models that match the given search
      # keywords.
      #
      #   class Article < ActiveRecord::Base
      #     sql_searchable_on :title, :body, :search_associated => [:comments]
      #     has_many :comments
      #   end
      #
      #   class Comment < ActiveRecord::Base
      #     sql_searchable_on :body
      #   end
      #
      #   Article.build_matching_included_model_ids_sql(Article.mirror.association[:comments], ['keyword1'])
      #     #=> "SELECT comments.id FROM comments WHERE (lower(comments.body) like '%keyword1%')"
      #
      def build_matching_included_model_ids_sql(ass_reflection, keywords)
        "SELECT #{ass_reflection.target_table}.#{ass_reflection.target_table_pk} FROM \
         #{ass_reflection.target_table} WHERE (#{ass_reflection.target_klass.build_sql_search_conditions_for(keywords.flatten)})"
      end
      
      protected
      
      # Merge any existing conditions into the freshly built search conditions
      def merged_conditions(search_conditions, other_conditions)
        other_conditions ? "(#{sanitize_sql(other_conditions)}) AND (#{search_conditions})" :
                           search_conditions
      end
    end
  end
end