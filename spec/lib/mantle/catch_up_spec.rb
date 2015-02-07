require 'spec_helper'

describe Mantle::CatchUp do
  let(:handler) { Mantle::CatchUp.new }
  let(:redis) { handler.redis }

  before :each do
    Mantle.configuration.message_bus_redis.flushdb
  end

  after :each do
    Mantle.configuration.message_bus_redis.flushdb
  end

  describe "#add_message" do
    it "adds message to redis that expires in 6 hours" do
      channel = "person:update"
      message = { id: 1 }
      json_message = JSON.generate(message)

      catch_up = Mantle::CatchUp.new
      catch_up.add_message(channel, message)

      json_payload = redis.zrange(catch_up.key, 0, -1).first
      channel, message = catch_up.deserialize_payload(json_payload)

      expect(channel).to eq(channel)
      expect(message).to eq(message)
    end
  end

  describe "#clear_expired" do
    it "clears expired entries from the catch up list" do
      cu = Mantle::CatchUp.new
      cu.add_message("person:update", { id: 1 }, 1.2456)
      cu.add_message("deal:update", { id: 2 }, 2.2456)
      cu.add_message("company:update", { id: 3 }, 3.2456)

      allow(Time).to receive_message_chain(:now, :utc, :to_f).and_return(3.0)

      cu.clear_expired

      expect(redis.zcount(cu.key, 0, 'inf')).to eq(1)

      json_payload = redis.zrange(cu.key, 0, -1).first
      channel, message = cu.deserialize_payload(json_payload)

      expect(channel).to eq("company:update")
    end
  end

  describe "catch_up" do
    it "raises when redis connection is missing" do
      cu = Mantle::CatchUp.new
      cu.redis = nil

      expect {
        cu.catch_up
      }.to raise_error(Mantle::Error::MissingRedisConnection)
    end
  end

  describe "#compare_times" do
    context "when the times are the same" do
      let(:t1) { 10_000 }
      let(:t2) { 10_000 }
      it "is false" do
        expect(handler.compare_times(t1, t2)).to be_falsey
      end
    end

    context "when the last digit is different" do
      let(:t1) { 10_000 }
      let(:t2) { 10_005 }
      it "is four" do
        expect(handler.compare_times(t1, t2)).to eq 4
      end
    end
    context "when the fourth digit is different" do
      let(:t1) { 10_000 }
      let(:t2) { 10_050 }
      it "is three" do
        expect(handler.compare_times(t1, t2)).to eq 3
      end
    end

    context "when the first digit is different" do
      let(:t1) { 10_000 }
      let(:t2) { 20_050 }
      it "is three" do
        expect(handler.compare_times(t1, t2)).to eq 0
      end
    end
  end

  describe "#sort_keys" do
    let(:keys) { ["action_list:1370533530.12034:contact:update:106", "action_list:1370533458.10278:contact:update:107", "action_list:1370533534.67259:contact:update:103", "action_list:1370533526.42493:contact:update:108"] }
    let(:sorted_keys) { ["action_list:1370533458.10278:contact:update:107", "action_list:1370533526.42493:contact:update:108", "action_list:1370533530.12034:contact:update:106", "action_list:1370533534.67259:contact:update:103"] }

    it "sorts the keys" do
      expect(handler.sort_keys(keys)).to eq sorted_keys
    end
  end

  describe "#get_keys_to_catch_up_on" do
    let(:keys) { ["action_list:1370533530.12034:contact:update:106", "action_list:1370533458.10278:contact:update:107", "action_list:1370533534.67259:contact:update:103", "action_list:1370533526.42493:contact:update:108"] }
    let(:keys_not_seen) { ["action_list:1370533530.12034:contact:update:106", "action_list:1370533534.67259:contact:update:103"] }

    it "finds the right keys" do
      redis = double("redis")
      handler.redis = redis

      allow(handler).to receive(:last_success_time) { Time.at(1370533_529) }
      allow(Time).to receive(:now) { Time.at(1370533_560) }
      allow(handler.redis).
        to receive(:keys).with("#{Mantle.configuration.message_bus_catch_up_key_name}:13705335*") { keys_not_seen }
      expect(handler.get_keys_to_catch_up_on).to eq keys_not_seen
    end
  end

  describe "#handle_messages_since_last_success" do
    let(:json) { "\"message\"" }
    let(:message_router) { double(route: true) }
    let(:redis) { double(get: json, keys: message) }

    before do
      handler.redis = redis
      handler.message_bus_channels = ["contact:update"]

      allow(handler).to receive(:last_success_time) { Time.at(1) }
      allow(Time).to receive(:now) { Time.at(2) }
      Mantle.logger.level = Logger::WARN
    end

    context 'message published on channel listed in Mantle.message_bus_channels' do
      let(:message) { ["action_list:1370533530.12034:contact:update:106"] }

      it "routes the messages" do
        expect(Mantle::MessageRouter).to receive(:new).with("contact", "update", json).and_return(message_router)
        handler.catch_up
      end
    end

    context 'message published on channel NOT listed in Mantle.message_bus_channels' do
      let(:message) { ["action_list:1370533530.12034:account:update:1"] }

      it "does not route the message" do
        expect(Mantle::MessageRouter).to_not receive(:new).with("account", "update", json)
        handler.catch_up
      end
    end
  end
end

