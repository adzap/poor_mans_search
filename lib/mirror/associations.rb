module YFactorial
  module Mirror
    
    # Provide more convenient access to the association reflections added to a class
    # via <tt>has_many</tt>, <tt>belongs_to</tt> etc...
    module Associations
      
      # Get access to the junk
      def self.included(base)
        base.extend(ClassMethods) 
      end
    
      module ClassMethods
        
        def mirror
          Mirror.new(self)
        end
      end
      
      class Mirror
        def initialize(klass)
          @klass = klass
        end
        def association
          AssociationMirror.new(@klass)
        end
      end
        
      class AssociationMirror

        def initialize(klass)
          @klass = klass
        end

        def [](assocation_name)
          Association.new(@klass, association_reflection_for(assocation_name))
        end

        private

        def association_reflection_for(assocation_name)
          ass_reflection = @klass.reflect_on_association(assocation_name)
          block_given? ? yield(ass_reflection) : ass_reflection
        end
      end
      
      class Association
        
        delegate :name, :to => :@reflection
        
        def initialize(klass, reflection)
          @klass = klass
          @reflection = reflection
        end
        
        def type
          @reflection.macro
        end
        
        def association_table
          through_reflection = @reflection.through_reflection
          through = through_reflection ? through_reflection.klass.table_name : nil
          through ? through : (@reflection.options[:join_table] ? @reflection.options[:join_table].intern : nil)
        end
        
        def target_table
          @reflection.klass.table_name.intern
        end

        def target_table_pk
          @reflection.klass.primary_key.intern
        end
        
        def queryable_table
          association_table || target_table
        end

        def target_klass
          @reflection.klass
        end
        
        def source_id_column
          through_reflection = @reflection.through_reflection
          through_reflection ? through_reflection.primary_key_name.intern : @reflection.primary_key_name.intern
        end

        def target_id_column
          through = association_table
          if through
            @reflection.association_foreign_key.intern
          else
            @reflection.klass.primary_key.intern
          end
        end
      end
    end
  end
end