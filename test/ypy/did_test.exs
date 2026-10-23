defmodule Ypy.DidTest do
  use ExUnit.Case, async: true

  alias Ypy.Did
  alias Ypy.Secp256k1

  test "derives the golden did:web from the tekoa domain" do
    assert Did.from_domain("tekoa.example.org") == "did:web:tekoa.example.org"
  end

  test "downcases and keeps single-label domains" do
    assert Did.from_domain("MinhaTekoa.Example.ORG") == "did:web:minhatekoa.example.org"
    assert Did.from_domain("box.local") == "did:web:box.local"
  end

  test "encodes a non-standard port as %3A" do
    assert Did.from_domain("tekoa.example.org:8443") == "did:web:tekoa.example.org%3A8443"
  end

  test "raises on a malformed domain" do
    for domain <- [
          "",
          "https://tekoa.example.org",
          "tekoa.example.org:",
          "tekoa.example.org:a",
          "tekoa.example.org:99999",
          "-tekoa.example.org",
          "tekoa..example.org",
          "tekoa.example-.org"
        ] do
      assert_raise ArgumentError, fn -> Did.from_domain(domain) end
    end
  end

  test "domain is the inverse of from_domain" do
    for domain <- ["tekoa.example.org", "box.local", "tekoa.example.org:8443"] do
      assert Did.domain(Did.from_domain(domain)) == domain
    end
  end

  test "domain refuses a non did:web" do
    assert_raise FunctionClauseError, fn -> Did.domain("did:plc:abc") end
  end

  test "builds the golden did document shape" do
    did = Did.from_domain("tekoa.example.org")
    multibase = Secp256k1.public_key_multibase(<<2, 1::256>>)

    assert Did.document(did, multibase) == %{
             "@context" => [
               "https://www.w3.org/ns/did/v1",
               "https://w3id.org/security/multikey/v1",
               "https://w3id.org/security/suites/secp256k1-2019/v1"
             ],
             "id" => "did:web:tekoa.example.org",
             "authentication" => ["did:web:tekoa.example.org#tekoa"],
             "verificationMethod" => [
               %{
                 "id" => "did:web:tekoa.example.org#tekoa",
                 "type" => "Multikey",
                 "controller" => "did:web:tekoa.example.org",
                 "publicKeyMultibase" => multibase
               }
             ]
           }
  end

  test "document refuses a non did:web subject (no PLC)" do
    assert_raise FunctionClauseError, fn -> Did.document("did:plc:xyz", "z6Mk") end
  end
end
