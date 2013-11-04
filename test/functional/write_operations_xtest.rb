# Copyright (C) 2013 MongoDB, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# run via
#   ruby -Ilib -Itest test/functional/write_operations_xtest.rb --verbose

require 'rbconfig'
require 'test_helper'
require 'benchmark'
require 'json'

MAX_BSON_SIZE = 16 * 1024 * 1024
TWEET_JSON = %q(
    { "text" : "Apple's New Multitouch IPod Nano - Associated Content http://bit.ly/aoICLJ", "in_reply_to_status_id" : null, "retweet_count" : null, "contributors" : null, "created_at" : "Thu Sep 02 18:11:31 +0000 2010", "geo" : null, "source" : "<a href=\"http://twitterfeed.com\" rel=\"nofollow\">twitterfeed</a>", "coordinates" : null, "in_reply_to_screen_name" : null, "truncated" : false, "entities" : { "user_mentions" : [], "urls" : [ { "indices" : [ 54, 74 ], "url" : "http://bit.ly/aoICLJ", "expanded_url" : null } ], "hashtags" : [] }, "retweeted" : false, "place" : null, "user" : { "friends_count" : 385, "profile_sidebar_fill_color" : "DDEEF6", "location" : "Los Angeles, CA", "verified" : false, "follow_request_sent" : null, "favourites_count" : 0, "profile_sidebar_border_color" : "C0DEED", "profile_image_url" : "http://a2.twimg.com/profile_images/1069735022/ipod_004_normal.png", "geo_enabled" : false, "created_at" : "Sun Jul 11 10:44:52 +0000 2010", "description" : "All About iPod and more...", "time_zone" : null, "url" : null, "screen_name" : "iPodMusicPlayer", "notifications" : null, "profile_background_color" : "C0DEED", "listed_count" : 10, "lang" : "en", "profile_background_image_url" : "http://a3.twimg.com/profile_background_images/121997947/iPod.jpg", "statuses_count" : 1504, "following" : null, "profile_text_color" : "333333", "protected" : false, "show_all_inline_media" : false, "profile_background_tile" : false, "name" : "iPod Music Player", "contributors_enabled" : false, "profile_link_color" : "0084B4", "followers_count" : 386, "id" : 165366606, "profile_use_background_image" : true, "utc_offset" : null }, "favorited" : false, "in_reply_to_user_id" : null, "id" : 22819405000 }
)
TWEET_COUNT = 51428 # in twitter.bson
TWEET_COUNT_TOO_BIG = 11749
TWEET = JSON.parse(TWEET_JSON)

def twitter_bulk_data
  twitter_file_name = "#{File.dirname(__FILE__)}/twitter.bson"
  twitter_file_size = File.size?(twitter_file_name)
  twitter_file = File.open(twitter_file_name)
  tweet = []
  while !twitter_file.eof? do
    tweet << BSON.read_bson_document(twitter_file)
    if tweet.size % 100 == 0
      STDOUT.print 100*twitter_file.pos/twitter_file_size
      print "\r"
    end
    #if tweet.size == 16000; then puts; p tweet.size; break; end
  end
  puts
  twitter_file.close
  tweet
end

def tweet_too_big_gen
  a = [ TWEET ]
  doc = {:tweet => a }
  bytes = BSON::BSON_CODER.serialize(doc, false, true, MAX_BSON_SIZE)
  (MAX_BSON_SIZE/bytes.size).times { a << TWEET.dup }
  begin
    a << TWEET.dup
    bytes = BSON::BSON_CODER.serialize(doc, false, true, MAX_BSON_SIZE) unless a.size < TWEET_COUNT_TOO_BIG
  rescue BSON::InvalidDocument => e
    #p e
    break
  end until bytes.size > MAX_BSON_SIZE
  doc
end

module Mongo
  class Collection

    @@verbose = false

    # exact copy of old committed implementation, but with public decl for insert_documents

    def insert_buffer(collection_name, continue_on_error)
      message = BSON::ByteBuffer.new("", @connection.max_message_size)
      message.put_int(continue_on_error ? 1 : 0)
      BSON::BSON_RUBY.serialize_cstr(message, "#{@db.name}.#{collection_name}")
      message
    end

    def insert_batch(message, documents, write_concern, continue_on_error, errors, collection_name=@name)
      begin
        send_insert_message(message, documents, collection_name, write_concern)
      rescue OperationFailure => ex
        raise ex unless continue_on_error
        errors << ex
      end
    end

    def send_insert_message(message, documents, collection_name, write_concern)
      instrument(:insert, :database => @db.name, :collection => collection_name, :documents => documents) do
        if Mongo::WriteConcern.gle?(write_concern)
          @connection.send_message_with_gle(Mongo::Constants::OP_INSERT, message, @db.name, nil, write_concern)
        else
          @connection.send_message(Mongo::Constants::OP_INSERT, message)
        end
      end
    end

    public

    # Sends a Mongo::Constants::OP_INSERT message to the database.
    # Takes an array of +documents+, an optional +collection_name+, and a
    # +check_keys+ setting.
    def insert_documents(documents, collection_name=@name, check_keys=true, write_concern={}, flags={})
      continue_on_error = !!flags[:continue_on_error]
      collect_on_error = !!flags[:collect_on_error]
      error_docs = [] # docs with errors on serialization
      errors = [] # for all errors on insertion
      batch_start = 0

      message = insert_buffer(collection_name, continue_on_error)

      documents.each_with_index do |doc, index|
        begin
          serialized_doc = BSON::BSON_CODER.serialize(doc, check_keys, true, @connection.max_bson_size)
        rescue BSON::InvalidDocument, BSON::InvalidKeyName, BSON::InvalidStringEncoding => ex
          raise ex unless collect_on_error
          error_docs << doc
          next
        end

        # Check if the current msg has room for this doc. If not, send current msg and create a new one.
        # GLE is a sep msg with its own header so shouldn't be included in padding with header size.
        total_message_size = Networking::STANDARD_HEADER_SIZE + message.size + serialized_doc.size
        if total_message_size > @connection.max_message_size
          docs_to_insert = documents[batch_start..index] - error_docs
          insert_batch(message, docs_to_insert, write_concern, continue_on_error, errors, collection_name)
          batch_start = index
          message = insert_buffer(collection_name, continue_on_error)
          redo
        else
          message.put_binary(serialized_doc.to_s)
        end
      end

      docs_to_insert = documents[batch_start..-1] - error_docs
      inserted_docs = documents - error_docs
      inserted_ids = inserted_docs.collect {|o| o[:_id] || o['_id']}

      # Avoid insertion if all docs failed serialization and collect_on_error
      if error_docs.empty? || !docs_to_insert.empty?
        insert_batch(message, docs_to_insert, write_concern, continue_on_error, errors, collection_name)
        # insert_batch collects errors if w > 0 and continue_on_error is true,
        # so raise the error here, as this is the last or only msg sent
        raise errors.last unless errors.empty?
      end

      collect_on_error ? [inserted_ids, error_docs] : inserted_ids
    end

    # new write command partition implementation

    def send_write_command(op, documents, opts, collection_name=@name)
      write_concern = get_write_concern(opts, self)
      opts[:writeConcern] = write_concern
      opts[:ordered] = true
      request = {op => collection_name, WRITE_COMMAND_ARG_KEY[op] => documents}.merge!(opts)
      #puts "send_write_command request: #{request.inspect}"
      response = @db.command(request)
      #puts "send_write_command response: #{response.inspect}"
      response
    end

    def batch_write_partition(op_type, documents, check_keys, opts, collection_name=@name)
      raise Mongo::OperationFailure, "Request contains no documents" if documents.empty?
      write_concern = get_write_concern(opts, self)
      continue_on_error = !!opts[:continue_on_error]
      collect_on_error = !!opts[:collect_on_error]
      error_docs = []
      errors = []
      responses = []
      inserted_docs = []
      @write_batch_size ||= BATCH_SIZE_LIMIT
      docs = documents.dup
      until docs.empty?
        batch = docs.take(@write_batch_size)
        begin
          if use_write_command?(write_concern)
            responses << send_write_command(op_type, batch, opts, collection_name)
          else
            responses << send_write_operation(op_type, nil, batch, check_keys, opts, collection_name)
          end
          inserted_docs.concat(batch)
          docs = docs.drop(batch.size)
          @write_batch_size = [(@write_batch_size*1097) >> 10, @write_batch_size+1].max unless docs.empty? # 2**(1/10) multiplicative increase
          @write_batch_size = BATCH_SIZE_LIMIT if @write_batch_size > BATCH_SIZE_LIMIT
        rescue BSON::InvalidDocument => ex # Document too large: This BSON document is limited to 16777216 bytes.
          raise ex if @write_batch_size == 1 # single document really is too large
          @write_batch_size = (@write_batch_size+1) >> 1 # 2**(-1) multiplicative decrease
        rescue => ex
          raise ex unless collect_on_error
          error_docs.concat(batch)
          docs = docs.drop(batch.size)
          errors << ex
        end
        puts "@write_batch_size: #{@write_batch_size}" if @@verbose
      end
      inserted_ids = inserted_docs.collect {|o| o[:_id] || o['_id']}
      collect_on_error ? [inserted_ids, error_docs, responses, errors] : inserted_ids
    end

    public :batch_write_incremental

  end
end

class TestCollection < Test::Unit::TestCase
  @@client ||= standard_connection(:op_timeout => 10)
  @@version = @@client.server_version
  @@db = @@client.db(MONGO_TEST_DB)
  @@test = @@db.collection("test")
  puts "@@version: #{@@version.inspect}"
  @@tweet = BSON.serialize(TWEET)
  puts "single tweet size: #{@@tweet.size}"
  @@tweet_batch_huge = TWEET_COUNT.times.collect{ TWEET.dup } #twitter_bulk_data
  puts "user bulk test tweet count: #{@@tweet_batch_huge.size}, estimated size: #{@@tweet.size * @@tweet_batch_huge.size}"
  @@tweet_too_big = tweet_too_big_gen
  #puts "@@tweet_too_big[:tweet].size: #{@@tweet_too_big[:tweet].size}"
  @@tweet_batch_big = @@tweet_too_big[:tweet].drop(1).collect{|doc| doc.dup}
  @@write_ops = [:insert, :update, :delete]
  @@write_batch_size = nil
  puts "----------------------------------------"

  MAX_WIRE_VERSIONS = [Mongo::MongoClient::RELEASE_2_4_AND_BEFORE,Mongo::MongoClient::BATCH_COMMANDS]

  def get_max_wire_version
    @@db.connection.instance_variable_get(:@max_wire_version)
  end

  def set_max_wire_version(n)
    @@db.connection.instance_variable_set(:@max_wire_version, n)
  end

  def with_max_wire_version(n)
    old_max_wire_version = get_max_wire_version
    new_max_wire_version = set_max_wire_version(n)
    #puts "max_wire_version: #{new_max_wire_version}"
    yield
    set_max_wire_version(old_max_wire_version)
  end

  def setup
    @@test.remove
  end

  def benchmark(title = nil)
    title ||= caller(1, 1)[0][/`(.*)'/, 1]
    GC.start
    GC.disable
    GC.stat
    bm = Benchmark.measure do
      yield
    end
    GC.stat
    GC.enable
    #puts "#{'%5.2f' % bm.utime} #{title}"
    bm
  end

  def verbose(value)
    old_value = Mongo::Collection.class_variable_get(:@@verbose)
    Mongo::Collection.class_variable_set(:@@verbose, value)
    yield
    Mongo::Collection.class_variable_set(:@@verbose, old_value)
  end

  BW_OPTS = {:w => 1}
  BENCHMARKS = [
    #[0,"insert_documents huge single w:0", @@tweet_batch_huge, Proc.new {|docs|docs.each{|tweet|@@test.insert_documents([tweet], 'test', false, {:w => 0})}}],
    #[0,"insert_documents huge single w:1", @@tweet_batch_huge, Proc.new {|docs|docs.each{|tweet|@@test.insert_documents([tweet], 'test', false, {:w => 1})}}],
    #[0,"insert_documents big w:1",         @@tweet_batch_big,  Proc.new {|docs|@@test.insert_documents(docs, 'test', false, {:w => 1})}],
    #[0,"batch_write_partition big w:1",    @@tweet_batch_big,  Proc.new {|docs|@@test.batch_write_partition(:insert, docs, false, BW_OPTS)}],
    #[0,"batch_write_partition big w:1",    @@tweet_batch_big,  Proc.new {|docs|@@test.batch_write_partition(:insert, docs, false, BW_OPTS)}],
    [0,"insert_documents huge w:1",        @@tweet_batch_huge, Proc.new {|docs|@@test.insert_documents(docs, 'test', false, BW_OPTS)}],
    [0,"batch_write_partition huge w:1",   @@tweet_batch_huge, Proc.new {|docs|@@test.batch_write_partition(:insert, docs, false, BW_OPTS)}],
    [2,"batch_write_partition huge w:1",   @@tweet_batch_huge, Proc.new {|docs|@@test.batch_write_partition(:insert, docs, false, BW_OPTS)}],
    [0,"batch_write_incremental huge w:1", @@tweet_batch_huge, Proc.new {|docs|@@test.batch_write_incremental(:insert, docs, false, BW_OPTS)}],
    [2,"batch_write_incremental huge w:1", @@tweet_batch_huge, Proc.new {|docs|@@test.batch_write_incremental(:insert, docs, false, BW_OPTS)}],
  ]

  def test_benchmark
    puts
    BENCHMARKS.each do |max_wire_version, title, docs, proc|
      verbose(false) do
        @@test.remove
        with_max_wire_version(max_wire_version) do
          bm = benchmark do
            proc.call(docs)
          end
          #result = {secs: bm.utime, docs_per_sec: (docs.size.to_f/bm.utime).round, mvw: max_wire_version, title: title}
          puts "secs:#{'%.2f' % bm.utime}, docs_per_sec:#{(docs.size.to_f/bm.utime).round}, max_wire_version:#{max_wire_version}, title:#{title.inspect}"
          assert_equal docs.size, @@test.count
        end
      end
    end
  end

  def test_insert_too_big
    assert_raise BSON::InvalidDocument do
      @@test.insert([@@tweet_too_big])
    end
  end

  if @@version >= "2.5.2"

    def test_batch_write_partition_too_big
      opts = {:writeConcern => {:w => 1}, :ordered => true}
      assert_raise BSON::InvalidDocument do
        @@test.batch_write_partition(:insert, [@@tweet_too_big], false, opts)
      end
    end

    def test_write_db_command
      op = :insert
      collection_name = @@test.name
      documents = (0..4).collect{|i| {:n => i}}
      opts = {:writeConcern => {:w => 1}, :ordered => true}
      request = {op => collection_name, Mongo::Collection::WRITE_COMMAND_ARG_KEY[op] => documents}.merge!(opts)
      response = @@db.command(request)
      assert_equal 5, response["n"]
    end

    def test_write_db_command_with_bson
      op = :insert
      collection_name = @@test.name
      documents = (0..4).collect{|i| {:n => i}}
      bson = BSON::BSON_CODER.serialize({}, false, false, @@db.connection.max_bson_size)
      bson.array(Mongo::Collection::WRITE_COMMAND_ARG_KEY[op])
      documents.each_with_index do |doc, index|
        serialization = BSON::BSON_CODER.serialize({index.to_s => doc}, false, false, @@db.connection.max_bson_size)
        bson.grow(serialization)
      end
      opts = {:writeConcern => {:j => 1}, :ordered => true}
      request = {op => collection_name, :bson => bson}.merge!(opts)
      response = @@db.command(request)
      assert_equal 5, response["n"]
    end

    def test_write_commands_insert_update_delete
      with_max_wire_version(Mongo::MongoClient::BATCH_COMMANDS) do
        documents = (0..4).collect{|i| {:n => i}}
        opts = {:writeConcern => {:j => 1}, :ordered => true, :collect_on_error => true}
        response = @@test.batch_write_partition(:insert, documents, false, opts) #@@test.insert(documents, opts) #
        #puts "response:#{response.inspect}"
        assert_equal 5, response[2][0]["n"]
        #puts "after insert #{@@test.find.to_a.inspect}"

        updates = [
              {:q => {:n => 1}, :u => {:n => 1, :y => 1}, :upsert => true},
              {:q => {:n => 3}, :u => {:n => 3, :y => 3}, :upsert => true},
              {:q => {:n => 5}, :u => {:n => 5, :y => 5}, :upsert => true},
              {:q => {:n => 7}, :u => {:n => 7, :y => 7}, :upsert => false},
              {:q => {:n => {'$gte' => 3}}, :u => {'$inc' => {:y => 1}}, :multi => true}
        ]
        opts = {:writeConcern => {:j => 1}, :ordered => true, :collect_on_error => true}
        response = @@test.batch_write_partition(:update, updates, false, opts) #@@test.update(updates, nil, opts) #
        puts "response:#{response.inspect}"
        assert_equal 5, response[2][0]["n"]
        assert_equal 1, response[2][0]["upserted"]
        #puts "after update #{@@test.find.to_a.inspect}"

        deletes = [{:q => {:n => 1}}, {:q => {:n => {'$gte' => 2}}, :limit => 2}] # SERVER-9038 limit not yet complete
        opts = {:writeConcern => {:j => 1}, :ordered => true, :collect_on_error => true}
        response = @@test.batch_write_partition(:delete, deletes, false, opts)
        #puts "response:#{response.inspect}"
        assert_equal 5, response[2][0]["n"]
        #puts "after remove #{@@test.find.to_a.inspect}"
        assert_equal 1, @@test.find.to_a.size
      end
    end

    def test_insert_wire_versions
      MAX_WIRE_VERSIONS.each do |wire_version|
        with_max_wire_version(wire_version) do
          [
            {:n => 1},
            [{:n => 1}, {:n => 2}]
          ].each do |docs|
            @@test.remove
            @@test.insert(docs)
            docs_a = docs.is_a?(Hash) ? [docs] : docs
            docs_a.each do |doc|
              assert_equal 1, @@test.find(doc).to_a.size
            end
          end
        end
      end
    end

    # TODO
    #   :ordered <-- ! :continue_on_error
    def test_batch_write_incremental_wire_versions
      #puts
      MAX_WIRE_VERSIONS.each do |wire_version|
        with_max_wire_version(wire_version) do
          documents = (0...5).collect{|i| {:n => i}}
          @@test.remove
          opts = {} #{:collect_on_error => true}
          response = @@test.batch_write_incremental(:insert, documents, true, opts)
          #puts "test_batch_insert_documents response: #{response}"
          assert_equal documents.size, @@test.count
          #p @@test.find.to_a
        end
      end
    end

  end

end
