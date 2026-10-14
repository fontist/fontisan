# frozen_string_literal: true

module Fontisan
  module SpecHelpers
    class BaselineCommandProbe < Commands::BaseCommand
      def run
        {
          font_path: font_path,
          font: font,
          options: options,
        }
      end
    end

    module BaselineCommandTestHelpers
      def run_conversion_with_coordinates(input_path, output_path, raw_coordinates, expected_coordinates)
        pipeline = double(
          transform: {
            details: {
              source_format: :ttf,
              target_format: :ttf,
              variation_strategy: :instance,
            },
          },
        )
        File.write(output_path, "font")
        allow(Pipeline::TransformationPipeline).to receive(:new)
          .and_return(pipeline)

        result = Commands::ConvertCommand.new(
          input_path,
          to: "ttf",
          output: output_path,
          coordinates: raw_coordinates,
          quiet: true,
        ).run

        expect(Pipeline::TransformationPipeline).to have_received(:new)
          .with(input_path, output_path,
                hash_including(coordinates: expected_coordinates))
        result
      end
    end
  end
end
