require "spec"
require "../src/main"

describe App do
  it "runs without errors" do
    # This is a very basic test to ensure the app doesn't crash.
    # We'll need to add more specific tests later.
    app = App.new
    # We need to mock the file system to test this properly.
    # For now, we'll just check that the App class can be instantiated.
    app.should_not be_nil
  end
end
