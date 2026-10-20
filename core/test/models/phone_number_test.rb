require "test_helper"

class PhoneNumberTest < ActiveSupport::TestCase
  test "normalises regional formats to E.164" do
    assert_equal "+41791234567", PhoneNumber.normalize("079 123 45 67")
    assert_equal "+4232321234", PhoneNumber.normalize("232 12 34")
    assert_equal "+436641234567", PhoneNumber.normalize("0043 664 1234567")
    assert_equal "+436641234567", PhoneNumber.normalize("0664 1234567")
    assert_equal "+491701234567", PhoneNumber.normalize("+49 170 1234567")
    assert_equal "+41791234567", PhoneNumber.normalize("+41 (0)79-123.45.67".delete("(0)"))
  end

  test "rejects garbage" do
    assert_nil PhoneNumber.normalize("")
    assert_nil PhoneNumber.normalize("hello")
    assert_nil PhoneNumber.normalize("12")
  end

  test "formats numbers for display" do
    assert_equal "+41 79 123 45 67", PhoneNumber.display("+41791234567")
    assert_equal "+423 232 12 34", PhoneNumber.display("+4232321234")
  end
end
