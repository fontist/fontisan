# frozen_string_literal: true

# Autoload hub for the Fontisan::Validators namespace.

module Fontisan
  module Validators
    autoload :BasicValidator, "fontisan/validators/basic_validator"
    autoload :FontBookValidator, "fontisan/validators/font_book_validator"
    autoload :OpenTypeValidator, "fontisan/validators/opentype_validator"
    autoload :ProfileLoader, "fontisan/validators/profile_loader"
    autoload :Validator, "fontisan/validators/validator"
    autoload :WebFontValidator, "fontisan/validators/web_font_validator"
  end
end
