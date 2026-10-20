require "test_helper"

# Every key must exist in every language, or a customer somewhere sees
# "translation missing".
class I18nConsistencyTest < ActiveSupport::TestCase
  def flat_keys(hash, prefix = nil)
    hash.flat_map do |key, value|
      path = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flat_keys(value, path) : [ path ]
    end
  end

  def keys_for(locale)
    flat_keys(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml")).fetch(locale)).to_set
  end

  test "German and English define the same keys" do
    de = keys_for("de")
    en = keys_for("en")
    assert_empty (de - en).to_a, "missing in en.yml"
    assert_empty (en - de).to_a, "missing in de.yml"
  end

  test "every enum value has a label" do
    %w[de en].each do |locale|
      I18n.with_locale(locale) do
        Booking::STATUSES.each { |s| assert I18n.exists?("statuses.#{s}"), "#{locale} statuses.#{s}" }
        Booking::SOURCES.each do |s|
          assert I18n.exists?("sources.#{s}"), "#{locale} sources.#{s}"
          assert I18n.exists?("sms.source.#{s}"), "#{locale} sms.source.#{s}"
        end
        CallLog::OUTCOMES.each { |o| assert I18n.exists?("call_outcomes.#{o}"), "#{locale} call_outcomes.#{o}" }
        Place::KINDS.each { |k| assert I18n.exists?("place_kinds.#{k}"), "#{locale} place_kinds.#{k}" }
        Actor::TYPES.each { |a| assert I18n.exists?("actors.#{a}"), "#{locale} actors.#{a}" }
        VehicleCategory::ALL.each { |c| assert I18n.exists?("vehicle_categories.#{c}"), "#{locale} #{c}" }
      end
    end
  end
end
