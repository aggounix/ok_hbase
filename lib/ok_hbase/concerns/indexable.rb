require 'ok_hbase/concerns/custom_row'

module OkHbase
  module Concerns
    module Indexable
      extend ActiveSupport::Concern
      include OkHbase::Concerns::CustomRow

      module ClassMethods
        def use_index(index_name, opts={})
          options = opts.with_indifferent_access
          attributes = options[:attributes]
          prefix_length = options[:prefix_length]
          index_id = options[:index_id]
          pack_pattern = options[:pack_pattern]
          auto_create = options[:auto_create]

          @@_indexes ||= {}
          @@_indexes = @@_indexes.with_indifferent_access
          @@_indexes[index_name] = options

          define_method :indexes do
            @@_indexes
          end


          define_method :key_for_index do |index_name, data|

            options = @@_indexes[index_name]
            row = self.class.row_class.new table: self, default_column_family: self.class.default_column_family, raw_data: data

            row_key_components = options[:attributes].map do |attribute|

              value = if attribute == :index_id
                options[:index_id]
              else
                row.raw_data[attribute] || row.send(attribute)
              end

              # coerce booleans to ints for packing
              value = 1 if value == true
              value = 0 if value == false

              # coerce hbase i64s to Fixnum, Bignum
              value = value.unpack('Q>').first if value.is_a?(String)


              value
            end

            row_key_components.pack(options[:pack_pattern].join(''))


          end

          define_method index_name do |idx_options, &block|
            expected_option_keys = attributes[0...prefix_length]
            prefix_pack_pattern = pack_pattern[0...prefix_length].join('')

            prefix_components = expected_option_keys.map do |key|
              key == :index_id ? index_id : idx_options[key]
            end

            row_prefix = prefix_components.pack(prefix_pack_pattern)

            scan(row_prefix: row_prefix, &block)
          end

          define_method :put do |row_key, data, timestamp = nil|
            self.batch(timestamp).transaction do |batch|
              @@_indexes.each_pair do |index_name, options|
                next unless options[:auto_create]

                index_row_key = key_for_index(index_name, data)

                batch.put(index_row_key, data)
              end
            end
          end
        end
      end
    end
  end
end
