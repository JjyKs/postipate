require 'httparty'
require 'json'
require 'byebug'
require 'mongo'
require "rb-readline"

AUTH_TOKEN = "xoxb-538199470724-538205125812-19Hsl21HRY4frx5UB1UphVJI"

def self.send(message, channel, mrkdwn = true)
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

def self.get_private_channel(user)
  auth = "Bearer " + AUTH_TOKEN

  slack_response = {
      users: [user]
  }

  a = HTTParty.post("https://slack.com/api/conversations.open",
                :headers => { 'Authorization' => auth, 'Content-Type' => 'application/json'}, :body => slack_response.to_json
  )
  return a["channel"]["id"]
end

connection = Mongo::Client.new([ '127.0.0.1:27017' ], :database => 'database')
db = connection[:parcels]

not_processed = db.find({notified: true})

not_processed.each do |t|
  t[:notified] = true
  db.update_one({id: t[:id]}, t)

  send("Paketilla *#{t[:code]}* on uusi tapahtuma: *#{t[:events][0]}*", get_private_channel(t[:user]))
end

connection.close


