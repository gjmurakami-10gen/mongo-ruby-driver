# New Write Operations

## Status
Pull request under review - old API fully working with new write commands, including new batch_write_incremental -
New fluent batch API ready for pull request and review

Responses and errors are complicated by the following.
1) top-level bulk operation is in-order grouped into second-level batches
2) each second-level batch can be large enough to split into third-level chunks
3) each third-level chunk can have a result or else an error
Observations
a) all results and errors are important
   if an exception is raised, results have to be incorporated into the error message
b) preserving the three-level result preserves information, flattening it looses information
c) it is complicated to scan the three-level result for simple success or failure

## Writeups
------------------------------------------------------------------------------------------------------------------------
# [Bulk API](https://github.com/10gen/specifications/blob/master/source/driver-bulk-update.rst)

also reference: [Fluent API](https://wiki.mongodb.com/display/10GEN/Fluent+Interface)

## Bulk API issues
  - Bulk Operation Builder > Operations Possible On Bulk Instance
    - upsert
      - upsert(false) needed(?) - with a mutable implementation, some mechanism is needed to "unstick" it
      - upsert as a modifier here is inconsistent with terminators upsert and upsertOne
        - we should make it consistent, suggest terminators - eliminates upsert.find order issue
          - suggested upsert, upsertOne, repsertOne
      - answer from Steve - implement the modifier as specified, Fluent spec will add upsert modifier (?)
## Bulk API questions
  - Does the query default to {} and is find optional for non-insert operations?
    - ex., bulk.remove === bulk.find({}).remove
  - is find sticky or volatile, is this mutable/immutable implementation dependent?
  - Given the current write command implementation, it is assumed that contiguous inserts (or contiguous updates,
    or contiguous deletes) will be submitted as a single batch.  This is not explicitly stated in the document,
    but it is somewhat inferred from the sections on merging errors and merging results.
    Also without batching of classes of ops, there would not be any performance gain for bulk operations.
    This should be stated very clearly.
  - What's the implementation difference between updateOne versus replaceOne?
    Is it just to check keys for replaceOne to reject $operators at the top level?
    Should we check keys to assert first $operator for update* operations?
## Bulk API Spec suggestions
  - Bulk Operation Builder
    - Operations Possible On Bulk Instance
      - supply example writeConcern

        var writeConcern = {w : 1, j : 1};
        bulk.execute(writeConcern);

  - Ordered Bulk Operations
    - ContinueOnError
      "Ordered operations are synonymous with continueOnError = true."
      I think that this is a mistake.
      Ordered operations stop on first error, which corresponds to NOT continuing on an error.
      Should be "Ordered operations are synonymous with continueOnError = false."
  - Unordered Bulk Operations
    - ContinueOnError
         "Unordered operations are synonymous with continueOnError = false."
         I think that this is a mistake.
         Unordered operations are all run independently, which corresponds to continuing on an error.
         Should be "Unordered operations are synonymous with continueOnError = true."
    - Merging errors
      - initializeBulkOp typo (?) - it is neither initializeOrderedBulkOp nor initializeUnorderedBulkOp
      - example does not cause an error for me
  - Unresolved
    - Comment:
      Need to consider the semantics of continueOnError in relation to bulk splitting. If continueOnError is true,
      the driver should stop sending additional write commands to the server
      on detection of an error in the previous bulk.
      Should be (If continueOnError is false):
      Need to consider the semantics of continueOnError in relation to bulk splitting. If continueOnError is false,
      the driver should stop sending additional write commands to the server
      on detection of an error in the previous bulk.
------------------------------------------------------------------------------------------------------------------------
#[Fluent API](https://wiki.mongodb.com/display/10GEN/Fluent+Interface)
- Fluent API questions
    how to unset limit, skip, sort, upsert
    limit versus top confusion
    upsert (multi) semantics
    upsert is a terminator in fluent and a modifier argument in bulk

- Fluent API design
    options
        bulk: @options[:bulk]
    op_args
        query: @op_args[:q] - selector
        update: @op_args[:u]
        project: @op_args[:project]
        upsert: @op_args[:upsert]
        limit: @op_args[:limit]
        other - fluent
        other - bulk
          :top
    pending
        FindAndModifyResult
        error raising
        $ checking

    def this_method
      caller[0][/`([^']*)'/, 1]
    end
------------------------------------------------------------------------------------------------------------------------
## Pending - In progress

pull requests submitted - peer review pending
  - batch_write_incremental

### TODO
- return values and errors - merge

- documentation

- maxBsonWireObjectSize
- batch_write_partition

- check options not leaking to server
- refactor send_write_operation and review any other large methods
- split Collection#insert into send_write_command and batch_write_incremental
- check nightly - 2013-10-24 top not yet working
- refactor instrument
(context for following - #insert ?)
- fluent pk_factory vs read preference and write concern

### Notes
- pull requests to be submitted - don't commit testing.rake
- rake test:commit runs replica_set et. al. for 2.4.6 but not 2.5.3 (yes, probably)

nightly 2013-10-16 and 2.5.3
- ordered is not optional (documentation says that it's optional) - errCode: '99999'; errMsg: 'missing ordered field'
- update top:0 and top:-1 only update one document
  - test_multi_update
- check_keys - test filtered out by version for now - TODO - review
  - test_update_check_keys
------------------------------------------------------------------------------------------------------------------------
## Completed
but to be reviewed again
- TODO and @@version .* "2.5.3"
- bulk check keys - update/update_one, replace_one, insert (via serialization)
- review/refactor calls to pk_factory.create_pk
- #find and #upsert immutable, #find! and #upsert! mutable
- implement upsert as modifier, no terminators for upsert, upsert_one, repsert_one
    module Mongo
      class BulkWriteCollectionView
        def upsert(u)
          raise MongoArgumentError, "document must start with an operator" unless update_doc?(u)
          op_push_and_return_self [:update, @op_args.merge(:u => u, :top => 0, :upsert => true)]
        end
        def upsert_one(u)
          raise MongoArgumentError, "document must start with an operator" unless update_doc?(u)
          op_push_and_return_self [:update, @op_args.merge(:u => u, :top => 1, :upsert => true)]
        end
        def repsert_one(u)
          raise MongoArgumentError, "document must not contain any operators" unless replace_doc?(u)
          op_push_and_return_self [:update, @op_args.merge(:u => u, :top => 1, :upsert => true)]
        end
      end
    end
    class BulkWriteCollectionViewTest < Test::Unit::TestCase
      context "Bulk API Spec Collection" do
        ...
        should "check arg for update, set :update, :u, :top, :upsert, terminate and return view for #upsert" do
          assert_raise MongoArgumentError do
            @bulk.find(@q).upsert(@r)
          end
          result = @bulk.find(@q).upsert(@u)
          assert_is_bulk_write_collection_view(result)
          assert_bulk_op_pushed [:update, {:q => @q, :u => @u, :top => 0, :upsert => true}], @bulk
        end

        should "check arg for update, set :update, :u, :top, :upsert, terminate and return view for #upsert_one" do
          assert_raise MongoArgumentError do
            @bulk.find(@q).upsert_one(@r)
          end
          result = @bulk.find(@q).upsert_one(@u)
          assert_is_bulk_write_collection_view(result)
          assert_bulk_op_pushed [:update, {:q => @q, :u => @u, :top => 1, :upsert => true}], @bulk
        end

        should "check arg for replacement, set :update, :u, :top, terminate and return view for #repsert_one" do
          assert_raise MongoArgumentError do
            @bulk.find(@q).repsert_one(@u)
          end
          result = @bulk.find(@q).repsert_one(@r)
          assert_is_bulk_write_collection_view(result)
          assert_bulk_op_pushed [:update, {:q => @q, :u => @r, :top => 1, :upsert => true}], @bulk
        end
        ...
              #@bulk.find({:a => 1}).upsert_one({"$inc" => { :x => 1 }})
              #@bulk.find({:a => 2}).upsert({"$inc" => { :x => 2 }})
              #@bulk.find({:a => 3}).repsert_one({ :x => 3 })
      end
    end
- writeConcern
- ordered = !continue_on_error
- BATCH_SIZE_LIMIT
- collect_on_error
- w:0 uses old write operations
- write_command should go to primary - yes, since not in SECONDARY_OK_COMMANDS
------------------------------------------------------------------------------------------------------------------------

### Benchmarks

#### How to run benchmarks

- start nightly server with write command support - at present works with 10-24 but NOT 11-02
- bundle install
- rake clobber
- rake compile
- ruby -Ilib -Itest test/functional/write_operations_xtest.rb

insert_documents - old batch implementation
- max_wire_version:0 - 1 serialize-call/document at high-level
batch_write_partition - new implementation with batch size adjusted for success
- max_wire_version:0 - 1 serialize-call/document at high-level
- max_wire_version:2 - 1 serialize-call/batch-insertion attempt
batch_write_incremental - new implementation - improved incremental
- 1 serialize-call/doc at high-level, new code
- 1 serialize-call/doc at high-level, new code with BSON grow

    secs:2.94, docs_per_sec:17493, max_wire_version:0, title:"insert_documents huge w:1"
    secs:1.34, docs_per_sec:38379, max_wire_version:0, title:"batch_write_partition huge w:1"
    secs:0.99, docs_per_sec:51947, max_wire_version:2, title:"batch_write_partition huge w:1"
    secs:2.16, docs_per_sec:23809, max_wire_version:0, title:"batch_write_incremental huge w:1"
    secs:2.47, docs_per_sec:20821, max_wire_version:2, title:"batch_write_incremental huge w:1"

## Jira tickets

- [RUBY-676 New write operation method for insert, update, remove](https://jira.mongodb.org/browse/RUBY-676)
- [DRIVERS-97 New write operation method for insert, update, remove](https://jira.mongodb.org/browse/DRIVERS-97)
- [SERVER-9038 New write operation method for insert, update, remove](https://jira.mongodb.org/browse/SERVER-9038)

## References

- [Write Commands Specification](https://github.com/10gen/specifications/blob/master/source/write-commands.rst)
- [Bulk API Spec](https://github.com/10gen/specifications/blob/master/source/driver-bulk-update.rst)
- [2.6 - New Write Op Codes](https://docs.google.com/a/10gen.com/document/d/1bsBi68ZwOzuDuRyAhYmaJay6DMKfc8XPH1EJJ50_RW8/edit)
- [Fluent Interface](https://wiki.mongodb.com/display/10GEN/Fluent+Interface)

## Features

1. bulk
2. continue on error mode
3. stats from each operation run (so you say continue on error and see which writes worked)
4. write concern built in (no more gle)

## References

- [New write operation method for insert, update, remove](https://jira.mongodb.org/browse/SERVER-9038)
- [Google doc: 2.6 - New Write Op Codes](https://docs.google.com/a/10gen.com/document/d/1bsBi68ZwOzuDuRyAhYmaJay6DMKfc8XPH1EJJ50_RW8/edit)

# mongod startup

The following is no longer needed as of nightly 2013-10-01

    mongod --setParameter enableExperimentalWriteCommands=true

# Ruby Interface

## Prototype Ruby Write Operations interface (by Gary)

### insert

Mongo::Collection#insert(doc_or_docs, opts={})
    was
Mongo::Collection#insert(doc_or_docs, opts={})

examples

    collection.insert(doc, :j => true)

    collection.insert(docs, :j => true, :continue_on_error => true, :collect_on_error => true)

#### insert_documents

Mongo::Collection#insert_documents(documents, collection_name=@name, check_keys=true, write_concern={}, flags={})

### update

Mongo::Collection#update(selector_or_updates, document_or_nil=nil, opts={})
    was
Mongo::Collection#update(selector, document, opts={})

examples

    collection.update({:n => 1}, {:p => 2}, :upsert => true, :multi => true, :j => true)

    collection.update([
            {:q => {:n => 2}, :u => {:n => 2, :p => 4}, :upsert => true, :multi => true},
            {:q => {:n => 3}, :u => {:n => 3, :p => 9}, :upsert => true}
        ],
        :j => true, :continue_on_error => true, :collect_on_error => true)

This exposes keys :q and :u to the user.
An alternative for the bulk/batch parameter would be to have each array element in the form [ query, update, opts ],
but this is more cumbersome than having each array element be a hash with key :q for the query and :u for update.

### delete

Mongo::Collection#remove(selector_or_deletes={}, opts={})
    was
Mongo::Collection#remove(selector={}, opts={})

examples

    collection.remove({:expire => {"$lte" => Time.now}}, :j => true)

    collection.remove([
            {:q => {:n => 1}, :limit => 1},
            {:q => {:n => {"$gt" => 2}}}
        ],
        :j => true, :continue_on_error => true, :collect_on_error => true)

This exposes key :q to the user.
An alternative for the bulk/batch parameter would be to have each array element in the form [ query, opts ],
but this is more cumbersome than having each array element be a hash with key :q for the query.

## Internals

Mongo::Collection#insert_documents(documents, collection_name=@name, check_keys=true, write_concern={}, flags={})

## Comments

As known, the update operation is the most complex.
The new update operation has non-trivial options, now at two levels.
For a bulk/batch operation, the top level has the common write concern and continue on error options,
while the inner level now has the upsert and multi options.

The delete operation also has options at two levels.
For a bulk/batch operation, the top level has the common write concern options,
while the inner level has the new limit option.

The user must explicitly specify options for the bulk/batch operations.
The driver does not supply any inherited semantics for the inner options.
Top level write concern options are inherited as previously specified and implemented in the Ruby API.

Ruby does not implement the remove just_one option.
The wire protocol has the SingleRemove flag for this function.
We need to develop a Ruby API for this function.

## Integration

As the new write operations are the future, the first approach would be to design with them as the core methods,
with fall-back to the old insert/update/delete operations.
The new write operations document a common core, so

The current low-level operations are:

Mongo::Collection#insert_batch(message, documents, write_concern, continue_on_error, errors, collection_name=@name)
Mongo::Collection#update(selector, document, opts={})
Mongo::Collection#remove(selector={}, opts={})

The new write operations are presented with a common core in the documentation.
This directs us to refactor to a common method for write operations #send_write_operation.

### Method #insert_documents

Refactoring is complicated by #insert_documents which is used twice and has a collection argument.
Simplify this by replacing the call in #generate_indexes with a call to a lower-level method.
Methods #insert_batch and #insert_buffer are used only in #insert_documents.

Insert calling sequence relevant to #insert_documents - there are no calls outside this chain after fixing #generate_indexes
  #save
    #insert
      #insert_documents
        #insert_buffer
        #insert_batch
          #send_insert_message # see also collection_test.rb:328

After much research and experimentation, the adaptive strategy for sizing write command is MIMD
(multiplicative increase and multiplicative decrease).
The decrease factor is -(1/2), corresponding to binary reduction (halving) for each attempt.
The increase factor is 2**(1/10) so that ten successful attempts corresponds to doubling.
The initial batch size is number of documents for first call.
This is probably better than 100, which gives 100x improvement over single writes, but reduction to 1 in about 7 attempts.

multiplicative increase / multiplicative decrease
-------------------------------------------------
initialize
    x = documents.size
multiplicative increase: x *= 2**(1/10)
    x = [(x * 1097) >> 10, x + 1].max unless documents.empty?
multiplicative decrease: x *= 2**(-1)
    x = [x >> 1, 1].max if failure

## Issues and remaining work items

What happens with a replica set containing a mix of server versions, where some nodes support the new write command and others do not?
We use the minimum of the maxWireVersion numbers, but what if all the nodes don't report in?

Check_keys is all or nothing, so any operator will force check_keys to be turned off for the rest of the BSON message.
Review check_keys

Underscore versus camelcase - document structure for batch requests is exposed, including some options that are camelcase.

Options need to be processed (rationalized, screened, translated) as appropriate.

Return values need to be examined carefully, along with the responses that are incorporated from the server.

Documentation of new batch insert, remove, and update.

Screening of proper usage for batch insert, remove, and update.
