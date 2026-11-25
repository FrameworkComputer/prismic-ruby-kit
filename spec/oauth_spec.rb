# encoding: utf-8
require 'spec_helper'

describe 'OAuth' do

  OAUTH_INITIATE_OPTS = {
    client_id: "client_id",
    redirect_uri: "http://myapp.com/callback",
    scope: "master+releases",
  }.freeze

  OAUTH_CHECKTOKEN_OPTS = {
    grant_type: "authorization_code",
    code: "thecode",
    redirect_uri: "http://myapp.com/callback",
    client_id: "client_id",
    client_secret: "client_secret",
  }

  describe "Public API", live: true do

    PUBLIC_URL = "https://micro.prismic.io/api"

    it "should accept unauthenticated requests" do
      expect {
        Prismic.api(PUBLIC_URL, nil)
      }.not_to raise_error()
    end

    describe "oauth_initiate_url" do

      it "should returns the URL" do
        url = Prismic::API.oauth_initiate_url(PUBLIC_URL, OAUTH_INITIATE_OPTS)
        expected_url = [
          "https://micro.prismic.io/auth?client_id=client_id",
          "redirect_uri=http%3A%2F%2Fmyapp.com%2Fcallback",
          "scope=master%2Breleases",
        ].join("&")
        url.should == expected_url
      end

      it "should returns the URL (with access_token)" do
        url = Prismic.oauth_initiate_url(PUBLIC_URL, OAUTH_INITIATE_OPTS, "token")
        expected_url = [
          "https://micro.prismic.io/auth?client_id=client_id",
          "redirect_uri=http%3A%2F%2Fmyapp.com%2Fcallback",
          "scope=master%2Breleases",
        ].join("&")
        url.should == expected_url
      end

    end

    describe "oauth_check_token" do

      it "should returns the URL" do
        expect {
          Prismic.oauth_check_token(PUBLIC_URL, OAUTH_CHECKTOKEN_OPTS)
        }.to raise_error(
          # we don't want to get a PrismicWSAuthError error here
          Prismic::API::PrismicWSConnectionError,
          "Can't connect to Prismic's API: 400 Bad Request"
        )
      end

    end

  end

  describe "Private API" do

    let(:url) { "https://private.prismic.io/api" }
    let(:auth_error_body) do
      JSON.dump(
        error: "Invalid access token",
        oauth_initiate: "https://private.prismic.io/auth",
        oauth_token: "https://private.prismic.io/auth/token",
      )
    end
    let(:http_client) { double(get: double(code: '401', body: auth_error_body, message: 'Unauthorized')) }
    let(:api_opts) { { http_client: http_client, api_cache: Prismic::BasicNullCache.new } }

    it "raises an auth error carrying the oauth endpoints" do
      expect {
        Prismic.api(url, api_opts)
      }.to raise_error(Prismic::API::PrismicWSAuthError) { |error|
        error.message.should == "Can't connect to Prismic's API: Invalid access token"
        error.oauth.initiate.should == "https://private.prismic.io/auth"
        error.oauth.token.should == "https://private.prismic.io/auth/token"
      }
    end

    it "builds the oauth initiate URL from the auth error" do
      initiate_url = Prismic.oauth_initiate_url(url, OAUTH_INITIATE_OPTS, api_opts)
      expected_url = [
        "https://private.prismic.io/auth?client_id=client_id",
        "redirect_uri=http%3A%2F%2Fmyapp.com%2Fcallback",
        "scope=master%2Breleases",
      ].join("&")
      initiate_url.should == expected_url
    end

    it "checks the token against the endpoint from the auth error" do
      http_client.should_receive(:post)
        .with("https://private.prismic.io/auth/token", OAUTH_CHECKTOKEN_OPTS)
        .and_return(double(code: '200', body: JSON.dump(access_token: "the_access_token")))
      Prismic.oauth_check_token(url, OAUTH_CHECKTOKEN_OPTS, api_opts).should == "the_access_token"
    end

  end

end
