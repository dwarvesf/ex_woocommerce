defmodule ExWoocommerce.Oauth do
    defstruct url: "", method: "GET", version: "v3", consumer_key: "", consumer_secret: "", signature_method: "", is_ssl: false

    def client(url, method, version, consumer_key, consumer_secret, signature_method \\ "HMAC-SHA256") do
      %ExWoocommerce.Oauth{
        url: url,
        method: String.upcase(method),
        version: version,
        consumer_key: consumer_key,
        consumer_secret: consumer_secret,
        signature_method: signature_method,
        is_ssl: String.starts_with?(url, "https://")
      }
    end

    # Public: Get OAuth url
    #
    # Returns the OAuth url.
    def get_oauth_url(client) do
      params = %{}
      url = client.url

      if String.contains?(url, "?") do
        parsed_url =  URI.parse(url)
        {_query, params} =
          Enum.map_reduce(
            URI.query_decoder(parsed_url.query),
            Keyword.new,
            fn {key, value}, acc ->
              {{key, value}, acc ++ Keyword.new([{String.to_atom(key), value}]) }
            end
          )
        sorted_params = Enum.sort(params)
        params = Map.new(sorted_params)
        url = parsed_url.authority
      end

      nonce_lifetime = 15 * 60 # Woocommerce keeps nonces for 15 minutes
      timestamp = DateTime.utc_now() |> DateTime.to_unix()
      nonce_encode = rem(timestamp, nonce_lifetime) + (System.unique_integer([:positive]) * nonce_lifetime) |> Integer.to_string
      params =
        params
        |> Map.put("oauth_consumer_key", client.consumer_key)
        |> Map.put("oauth_nonce", :crypto.hash(:sha, nonce_encode) |> Base.encode16)
        |> Map.put("oauth_signature_method", client.signature_method)
        |> Map.put("oauth_timestamp", timestamp)
      params = Map.put(params, "oauth_signature", URI.encode(generate_oauth_signature(client, params, url)))
      q = Enum.map(Enum.sort(params), fn {key, value} -> "#{key}=#{value}" end) |> Enum.join("&")
      query_string = URI.encode(q)
      "#{url}?#{query_string}"
    end


    # Internal: Generate the OAuth Signature
    #
    # params - A Hash with the OAuth params.
    # url    - A String with a URL
    #
    # Returns the oauth signature String.
    def generate_oauth_signature(client, params, url) do
      base_request_uri = URI.encode(url)
      query_params = []

      query_string = Enum.map(
        Enum.sort(params), fn {key, value} ->
          encode_param(key) <> "%3D" <> encode_param(value)
        end) |> Enum.join("%26")

      string_to_sign = "#{client.method}&#{base_request_uri}&#{query_string}"
      IO.inspect string_to_sign

      consumer_secret = "#{client.consumer_secret}&"
      :crypto.hmac(digest(client), consumer_secret, string_to_sign)
      |> Base.encode64
    end

    # Internal: Digest object based on signature method
    #
    # Returns a digest object.
    def digest(client) do
      case client.signature_method do
        "HMAC-SHA256" -> :sha256
        "HMAC-SHA1" -> :sha1
      end
    end

    # Internal: Encode param
    #
    # text - A String to be encoded
    #
    # Returns the encoded String.
    def encode_param(text) do
      esc = URI.encode("#{text}")
      esc = String.replace(esc, "+", "%20")
      String.replace(esc, "%", "%25")
    end
end
