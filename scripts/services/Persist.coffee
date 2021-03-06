"use strict"

###*
 # @ngdoc service
 # @name Persist
 # @requires $q, $http, SyncCollectionsConfig, Loader, Storage
 # @description
 # Service used to retrieve collections from the database
 # This service used to retrieve and persist objects from the Storage.
 # @example
 # # With a model
```js
promise = Persist.init "humans", Human
promise.then -> humans = Persist.get "humans"
```
 # # without default model
```js
config = Persist.init "config"
config.perPage = 20
Persist.save config
```
 # # delete everything
```js
Persist.reset()
```
###
angular.module("syncCollections").factory "Persist", ($q, $http, $timeout, $injector, SyncCollectionsConfig, Loader) ->
	Storage = $injector.get(SyncCollectionsConfig.store);
	persistable = {}
	resyncPromise = null
	getCounter = (name) ->
		deferred = $q.defer()
		Storage.get("counter_#{name}").then (counter) =>
			if counter
				counter = parseInt counter, 10
			else
				counter = 0
			deferred.resolve counter
		deferred.promise

	reset: ->
		persistable = {}
		Storage.reset()
	resync: ->
		return resyncPromise  if resyncPromise
		promises = []
		for k, p of persistable
			deferred = $q.defer()
			@_checkCounterAndLoad deferred, p.name, p.modelClass
			promises.push deferred.promise
		resyncPromise = $q.all promises
		resyncPromise.then -> resyncPromise = null
		resyncPromise
	load: (resync = true) ->
		if Loader.isLoading()
			Loader.load()
		else if resync
			@resync()
		else
			$q (resolve) -> resolve()
	isLoading: -> Loader.isLoading()
	checkCounters: ->
		promises = []
		for k, p of persistable
			deferred = $q.defer()
			@_checkCounter deferred, p.name, p.modelClass
			promises.push deferred.promise
		$q.all promises
	init: (collectionName, Model) ->
		deferred = $q.defer()
		@_checkCounterAndLoad deferred, collectionName, Model
		Loader.addPromise deferred.promise
		deferred.promise
	get: (collectionName) -> persistable[collectionName]?.collection || throw "Collection #{collectionName} does not exist"
	_checkCounter: (deferred, collectionName, Model) ->
		getCounter(collectionName).then (counter) =>
			$http.get("#{SyncCollectionsConfig.apiUrl}/counter/#{collectionName}", {withCredentials: SyncCollectionsConfig.withCredentials, timeout: SyncCollectionsConfig.requestTimeout})
			.success (remoteCounter) -> deferred.resolve counter is remoteCounter.counter
			.error -> deferred.reject()
	_checkCounterAndLoad: (deferred, collectionName, Model) ->
		getCounter(collectionName).then (counter) =>
			@_updateCollection deferred, collectionName, Model, counter
	_updateCollection: (deferred, collectionName, Model, counter, retry = 0) ->
		if window.cordova and navigator.connection?.type is Connection.NONE
			@_getLocalCollection deferred, collectionName, Model
		else
			$http.get("#{SyncCollectionsConfig.apiUrl}/counter/#{collectionName}", {withCredentials: SyncCollectionsConfig.withCredentials, timeout: 2 * SyncCollectionsConfig.requestTimeout})
			.success (remoteCounter) =>
				if counter is remoteCounter.counter
					@_getLocalCollection deferred, collectionName, Model
				else
					@_fetchCollection deferred, collectionName, Model, remoteCounter.counter
			.error =>
				if retry++ < SyncCollectionsConfig.retryCount
					console.error "Could not get the counter for #{collectionName}, retry in 500ms (#{retry}/#{SyncCollectionsConfig.retryCount})"
					$timeout =>
						@_updateCollection deferred, collectionName, Model, counter, retry
					, SyncCollectionsConfig.retryDelay
				else
					console.error "Could not get the counter for #{collectionName}, you may be offline? Getting local collection"
					@_getLocalCollection deferred, collectionName, Model
	_fetchCollection: (deferred, collectionName, Model, counter) ->
		$http.get("#{SyncCollectionsConfig.apiUrl}/#{collectionName}", {withCredentials: SyncCollectionsConfig.withCredentials, timeout: 5 * SyncCollectionsConfig.requestTimeout})
		.success (collection) =>
			Storage.set(collectionName, collection, counter).then =>
				@_getLocalCollection deferred, collectionName, Model
		.error =>
			console.error "Could not fetch the collection #{collectionName}, you may be offline? Getting local collection"
			Storage.set "counter_#{collectionName}", 0 # Make sure we try again next time
			@_getLocalCollection deferred, collectionName, Model
	_getLocalCollection: (deferred, collectionName, Model) ->
		Storage.get(collectionName).then (collection) =>
			if persistable[collectionName]
				persistable[collectionName].collection.length = 0
			else
				persistable[collectionName] =
					collection: []
					modelClass: Model
					name: collectionName
			if collection and angular.isArray(collection)
				persistable[collectionName].collection.push(new Model literal)  for literal in collection
			else
				Storage.set collectionName, "[]", 0
			deferred.resolve persistable[collectionName].collection

