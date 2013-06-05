class CatchUpHandler
  def initialize(listener)
    @listener = listener
  end

  def catch_up!
    time = Settings.last_success
    return unless time.present?
    sig_length = compare_times(Time.now.to_i.to_s, time.to_i.to_s)
    return unless sig_length.present?
    prefix = time.to_i.to_s[0, sig_length]
    keys = @listener.redis.keys("jupiter:action_list:#{prefix}*")
    handle_messages_since_last_success(time, keys)
  end

  def compare_times(t1, t2)
    for i in 0...t1.length do return i if t1[i] != t2[i] end
    false
  end

  def handle_messages_since_last_success(time, keys)
    keys.each do |key|
      ns, list, timestamp, model, action, id = key.split(':')
      if timestamp.to_f > time
        channel = "#{@namespace}:#{action}:#{model}"
        message = @redis.get key
        @listener.receive(channel, message)
      end
    end
  end
end
