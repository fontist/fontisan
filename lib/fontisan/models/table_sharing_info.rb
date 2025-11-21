# frozen_string_literal: true

require "lutaml/model"

module Fontisan
  module Models
    # Model for table sharing statistics
    #
    # Represents table deduplication information in a TTC/OTC collection.
    # Shows which tables are shared between fonts.
    #
    # @example Creating table sharing info
    #   sharing = TableSharingInfo.new(
    #     shared_tables: 12,
    #     unique_tables: 48,
    #     sharing_percentage: 20.0,
    #     space_saved_bytes: 156300
    #   )
    class TableSharingInfo < Lutaml::Model::Serializable
      attribute :shared_tables, :integer
      attribute :unique_tables, :integer
      attribute :sharing_percentage, :float
      attribute :space_saved_bytes, :integer

      yaml do
        map "shared_tables", to: :shared_tables
        map "unique_tables", to: :unique_tables
        map "sharing_percentage", to: :sharing_percentage
        map "space_saved_bytes", to: :space_saved_bytes
      end

      json do
        map "shared_tables", to: :shared_tables
        map "unique_tables", to: :unique_tables
        map "sharing_percentage", to: :sharing_percentage
        map "space_saved_bytes", to: :space_saved_bytes
      end
    end
  end
end
