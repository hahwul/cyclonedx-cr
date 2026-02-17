require "spec"
require "../../src/cyclonedx/bom"
require "uuid"

describe CycloneDX::BOM do
  describe "serialNumber consistency" do
    it "has a consistent serial number across XML generations" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.4")

      xml1 = bom.to_xml
      xml2 = bom.to_xml

      match1 = xml1.match(/serialNumber="([^"]+)"/)
      match2 = xml2.match(/serialNumber="([^"]+)"/)

      match1.should_not be_nil
      match2.should_not be_nil

      if match1 && match2
        # This is expected to fail before the fix
        match1[1].should eq(match2[1])
        match1[1].should start_with("urn:uuid:")
      end
    end

    it "includes serialNumber in JSON output matching the object state" do
      components = [] of CycloneDX::Component
      bom = CycloneDX::BOM.new(components, "1.4")

      # Generate XML to potentially trigger lazy initialization if it were implemented that way (it's not, but good practice)
      xml = bom.to_xml
      match_xml = xml.match(/serialNumber="([^"]+)"/)
      match_xml.should_not be_nil

      # Check JSON
      json = bom.to_json
      # This is expected to fail before the fix as serialNumber is missing
      json.should contain("serialNumber")

      if match_xml
        json.should contain(match_xml[1])
      end
    end
  end
end
