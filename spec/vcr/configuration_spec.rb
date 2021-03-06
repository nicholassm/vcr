require 'spec_helper'

describe VCR.configuration do
  def stub_no_http_stubbing_adapter
    VCR.stub(:http_stubbing_adapter).and_raise(ArgumentError)
    VCR.configuration.stub(:http_stubbing_libraries).and_return([])
  end

  describe '.cassette_library_dir=' do
    let(:tmp_dir) { VCR::SPEC_ROOT + '/../tmp/cassette_library_dir/new_dir' }
    after(:each) { FileUtils.rm_rf tmp_dir }

    it 'creates the directory if it does not exist' do
      expect { VCR.configuration.cassette_library_dir = tmp_dir }.to change { File.exist?(tmp_dir) }.from(false).to(true)
    end

    it 'does not raise an error if given nil' do
      expect { VCR.configuration.cassette_library_dir = nil }.to_not raise_error
    end
  end

  describe '.default_cassette_options' do
    it 'has a hash with some defaults even if it is set to nil' do
      VCR.configuration.default_cassette_options = nil
      VCR.configuration.default_cassette_options.should eq({
        :match_requests_on => VCR::RequestMatcher::DEFAULT_MATCH_ATTRIBUTES,
        :record            => :once
      })
    end

    it "returns #{VCR::RequestMatcher::DEFAULT_MATCH_ATTRIBUTES.inspect} for :match_requests_on when other defaults have been set" do
      VCR.configuration.default_cassette_options = { :record => :none }
      VCR.configuration.default_cassette_options.should include(:match_requests_on => VCR::RequestMatcher::DEFAULT_MATCH_ATTRIBUTES)
    end

    it "returns :once for :record when other defaults have been set" do
      VCR.configuration.default_cassette_options = { :erb => :true }
      VCR.configuration.default_cassette_options.should include(:record => :once)
    end
  end

  describe '.stub_with' do
    it 'stores the given symbols in http_stubbing_libraries' do
      VCR.configuration.stub_with :fakeweb, :typhoeus
      VCR.configuration.http_stubbing_libraries.should eq([:fakeweb, :typhoeus])
    end
  end

  describe '.http_stubbing_libraries' do
    it 'returns an empty array even when the variable is nil' do
      VCR.configuration.send(:remove_instance_variable, :@http_stubbing_libraries)
      VCR.configuration.http_stubbing_libraries.should eq([])
    end
  end

  describe '.ignore_hosts' do
    let(:stubbing_adapter) { VCR::HttpStubbingAdapters::FakeWeb }
    before(:each) do
      stubbing_adapter.send(:ignored_hosts).should be_empty
      VCR.stub(:http_stubbing_adapter => stubbing_adapter)
      VCR.configuration.ignored_hosts.should be_empty
    end

    it 'adds the given hosts to the ignored_hosts list' do
      VCR.configuration.ignore_hosts 'example.com', 'example.net'
      VCR.configuration.ignored_hosts.should eq(%w[ example.com example.net ])
      VCR.configuration.ignore_host 'example.org'
      VCR.configuration.ignored_hosts.should eq(%w[ example.com example.net example.org ])
    end

    it 'removes duplicate hosts' do
      VCR.configuration.ignore_host 'example.com'
      VCR.configuration.ignore_host 'example.com'
      VCR.configuration.ignored_hosts.should eq(['example.com'])
    end

    it "updates the http_stubbing_adapter's ignored_hosts list" do
      VCR.configuration.ignore_hosts 'example.com', 'example.org'
      stubbing_adapter.send(:ignored_hosts).should eq(%w[ example.com example.org ])
    end
  end

  describe '.ignore_localhost=' do
    before(:each) do
      VCR.configuration.ignored_hosts.should be_empty
    end

    it 'adds the localhost aliases to the ignored_hosts list when set to true' do
      VCR.configuration.ignore_host 'example.com'
      VCR.configuration.ignore_localhost = true
      VCR.configuration.ignored_hosts.should eq(['example.com', *VCR::LOCALHOST_ALIASES])
    end

    it 'removes the localhost aliases from the ignored_hosts list when set to false' do
      VCR.configuration.ignore_host 'example.com', *VCR::LOCALHOST_ALIASES
      VCR.configuration.ignore_localhost = false
      VCR.configuration.ignored_hosts.should eq(['example.com'])
    end
  end

  describe '.allow_http_connections_when_no_cassette=' do
    [true, false].each do |val|
      it "sets the allow_http_connections_when_no_cassette to #{val} when set to #{val}" do
        VCR.configuration.allow_http_connections_when_no_cassette = val
        VCR.configuration.allow_http_connections_when_no_cassette?.should eq(val)
      end
    end

    it 'sets http_connnections_allowed to the default' do
      VCR.http_stubbing_adapter.should respond_to(:set_http_connections_allowed_to_default)
      VCR.http_stubbing_adapter.should_receive(:set_http_connections_allowed_to_default)
      VCR.configuration.allow_http_connections_when_no_cassette = true
    end

    it "works when the adapter hasn't been set yet" do
      stub_no_http_stubbing_adapter
      VCR.configuration.allow_http_connections_when_no_cassette = true
    end
  end

  describe '.uri_should_be_ignored?' do
    before(:each) { described_class.ignore_hosts 'example.com' }

    it 'returns true for a string URI with a host in the ignore_hosts list' do
      described_class.uri_should_be_ignored?("http://example.com/").should be_true
    end

    it 'returns true for a URI instance with a host in the ignore_hosts list' do
      described_class.uri_should_be_ignored?(URI("http://example.com/")).should be_true
    end

    it 'returns false for a string URI with a host in the ignore_hosts list' do
      described_class.uri_should_be_ignored?("http://example.net/").should be_false
    end

    it 'returns false for a URI instance with a host in the ignore_hosts list' do
      described_class.uri_should_be_ignored?(URI("http://example.net/")).should be_false
    end
  end

  describe '.filter_sensitive_data' do
    let(:interaction) { mock('interaction') }
    before(:each) { interaction.stub(:filter!) }

    it 'adds a before_record hook that replaces the string returned by the block with the given string' do
      described_class.filter_sensitive_data('foo', &lambda { 'bar' })
      interaction.should_receive(:filter!).with('bar', 'foo')
      described_class.invoke_hook(:before_record, nil, interaction)
    end

    it 'adds a before_playback hook that replaces the given string with the string returned by the block' do
      described_class.filter_sensitive_data('foo', &lambda { 'bar' })
      interaction.should_receive(:filter!).with('foo', 'bar')
      described_class.invoke_hook(:before_playback, nil, interaction)
    end

    it 'tags the before_record hook when given a tag' do
      described_class.should_receive(:before_record).with(:my_tag)
      described_class.filter_sensitive_data('foo', :my_tag) { 'bar' }
    end

    it 'tags the before_playback hook when given a tag' do
      described_class.should_receive(:before_playback).with(:my_tag)
      described_class.filter_sensitive_data('foo', :my_tag) { 'bar' }
    end

    it 'yields the interaction to the block for the before_record hook' do
      yielded_interaction = nil
      described_class.filter_sensitive_data('foo', &lambda { |i| yielded_interaction = i; 'bar' })
      described_class.invoke_hook(:before_record, nil, interaction)
      yielded_interaction.should equal(interaction)
    end

    it 'yields the interaction to the block for the before_playback hook' do
      yielded_interaction = nil
      described_class.filter_sensitive_data('foo', &lambda { |i| yielded_interaction = i; 'bar' })
      described_class.invoke_hook(:before_playback, nil, interaction)
      yielded_interaction.should equal(interaction)
    end
  end
end
