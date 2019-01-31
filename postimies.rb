require 'sinatra/base'
require 'byebug'
require 'httparty'
require 'json'
AUTH_TOKEN = "xoxb-538199470724-538205125812-GrDcmofI4OjlPoUipCjidSEZ"

class Postimies < Sinatra::Base
  set(:method) do |method|
    method = method.to_s.upcase
    condition { request.request_method == method }
  end

  before :method => :post do
    request.body.rewind
    @request_payload = JSON.parse request.body.read
  end

  before do
    @mongo = settings.mongo_db
  end

  post '/slack/event' do
    slack_event = @request_payload["event"]
    halt(200) if slack_event["edited"]
    user = slack_event["user"]
    channel = slack_event["channel"]
    tracking_code = parse_tracking_code(slack_event["text"])



    begin
      response = HTTParty.post("https://www.posti.fi/henkiloasiakkaat/seuranta/api/shipments",
                               body: {trackingCodes: [tracking_code]}.to_json,
                               :headers => { 'Content-Type' => 'application/json'
                               })

      if (response.code == 200)
        r = JSON.parse(response.body)
        unparsed_events = r["shipments"][0]["events"]
        events = []
        unparsed_events.each_with_index do |event, index|
          events << event["description"]["fi"]
        end
        id = "#{user}_#{tracking_code}"
        data = {id: id, user: user, code: tracking_code, events: events, notified: false}
      end

      old_state = @mongo.find({id: id}).first
      if (old_state.nil?)
        @mongo.insert_one(data)
        send("Paketti *#{tracking_code}* lisätty seurantaan. \n Viimeisin tapahtuma: *#{data[:events][0]}*", channel)
      else
        if data[:events] != old_state["events"]
          data[:notified] = true
          @mongo.update_one({id: id}, data)
          send("Paketilla *#{tracking_code}* on uusi tapahtuma: *#{data[:events][0]}*", channel)
        else
          send("Ei uusia tapahtumia paketille *#{tracking_code}*. \n Viimeisin tapahtuma: *#{data[:events][0]}*", channel)
        end
      end


    rescue StandardError => e
      send("Hajosin. Kerro Jypelle että: \n #{e.inspect} \n #{e.backtrace[0]} \n TrackingCode: #{tracking_code}", channel, false)
    end

    halt 200
  end

  configure do
    db = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'database')
    set :mongo_db, db[:parcels]
  end


  private
  def parse_tracking_code input
    begin
      return /JJFI(\d+)/.match(input)[0]
    rescue
      return ""
    end
  end

  def send(message, channel, mrkdwn = true)
    auth = "Bearer " + AUTH_TOKEN

    slack_response = {
        text: message,
        channel: channel,
        mrkdwn: mrkdwn
    }

    HTTParty.post("https://slack.com/api/chat.postMessage",
                      :headers => { 'Authorization' => auth, 'Content-Type' => 'application/json'}, :body => slack_response.to_json
                      )

    puts "Sent message #{message} to channel #{channel}"

  end

end
