# encoding: utf-8
require 'spec_helper'

describe Prismic::DefaultHTTPClient do
  let(:http) { instance_double(Net::HTTP, :use_ssl= => nil, get: nil, post: nil) }
  let(:uri) { URI('https://micro.prismic.io/api') }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
  end

  describe '.get' do
    it 'sends the token once per call without changing the given URI' do
      2.times { described_class.get(uri, 'access_token' => 'abc') }

      expect(uri.to_s).to eq('https://micro.prismic.io/api')
      expect(http).to have_received(:get).with('/api?access_token=abc', {}).twice
    end
  end

  describe '.post' do
    it 'sends the token once per call without changing the given URI' do
      2.times { described_class.post(uri, 'access_token' => 'abc') }

      expect(uri.to_s).to eq('https://micro.prismic.io/api')
      expect(http).to have_received(:post).with('/api', 'access_token=abc', {}).twice
    end
  end
end
