# "CHF 280" / "ca. CHF 45.50". Shared by controllers (JSON) and views.
module PriceFormatting
  def format_price(cents, currency, estimated: false)
    return I18n.t("price.on_request") if cents.nil?

    amount = ActiveSupport::NumberHelper.number_to_rounded(
      cents / 100.0, precision: (cents % 100).zero? ? 0 : 2, delimiter: "'"
    )
    [ (I18n.t("price.approx") if estimated), currency, amount ].compact.join(" ")
  end
end
