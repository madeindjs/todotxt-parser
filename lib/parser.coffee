_ = require "underscore"

buildPattern = (opt) ->
  # returns interpolation-friendly regex
  interp = (expr) ->
    expr().toString()[1..-2]

  DATE = -> opt.dateRegex || /\d{4}-\d{2}-\d{2}/
  START = -> if opt.relaxedWhitespace then /^\s*/ else /^/
  SPACE = -> if opt.relaxedWhitespace then /\s+/ else /\s/
  COMPLETE = -> ///
    (x)#{if opt.requireCompletionDate then interp SPACE else ""}
    (#{interp DATE})#{if opt.requireCompletionDate then "" else "?"}
  ///
  PRIORITY = -> if opt.ignorePriorityCase then /\(([A-Za-z])\)/ else /\(([A-Z])\)/

  ///
    #{interp START}
    (?:#{interp COMPLETE}#{interp SPACE})?  # completion mark and date
    (?:#{interp PRIORITY}#{interp SPACE})?  # priority
    (?:(#{interp DATE})#{interp SPACE})?    # created date
    (.*)                                    # task text (may contain +projects, @contexts, meta:data)
    $
  ///

module.exports =
  parse: (s, options = {}) ->
    # the defaults adhere to Gina Trapani's vanilla/canonical todo.txt-cli format & implementation
    _.defaults options,
      dateParser: (s) -> Date.parse s
      dateRegex: null
      relaxedWhitespace: false
      requireCompletionDate: true
      ignorePriorityCase: false
      heirarchical: false
      commentRegex: null
      projectRegex: /\s\+(\S+)/g
      contextRegex: /\s@(\S+)/g
      # collection of functions that parse the task text and return key:value objects
      extensions: []

    pattern = buildPattern options
    root = {subtasks: [], indentLevel: -1, text: "root"}
    stack = [root]

    for line in s.split "\n"
      taskMatch = line.match pattern
      commentMatch = if options.commentRegex then line.match options.commentRegex
      if !taskMatch or commentMatch then continue

      text = taskMatch[5].trim()
      projects = while match = options.projectRegex.exec text
        match[1]
      contexts = while match = options.contextRegex.exec text
        match[1]
      metadata = {}
      for dataParser in options.extensions
        data = dataParser text
        for key, value of data
          metadata[key] = value

      task =
        raw: taskMatch[0]
        text: text
        projects: projects
        contexts: contexts
        complete: taskMatch[1]?
        dateCreated: if taskMatch[4] then options.dateParser taskMatch[4] else null
        dateCompleted: if taskMatch[2] then options.dateParser taskMatch[2] else null
        priority: (taskMatch[3] || metadata.pri)?.toUpperCase() || null
        metadata: metadata
        subtasks: []
        indentLevel: if match = line.match /^(\s+).+/
            # if line starts with a space, then count the number of leading whitespace characters
            match[1].length
          else if match = line.match /^x(\s+).+/
            # if line starts with x, then count the whitespace after it + 1 (for the x)
            match[1].length + 1
          else 0

      prevSibling = _.last(_.last(stack).subtasks) || _.last(stack)
      if task.indentLevel > prevSibling.indentLevel
        stack.push prevSibling
      while task.indentLevel <= _.last(stack).indentLevel
        stack.pop()
      _.last(stack).subtasks.push task

    root.subtasks


  # parsing function with default values
  canonical: (s) ->
    module.exports.parse s

  # parsing function with relaxed options
  relaxed: (s, options = {}) ->
    module.exports.parse s, _.defaults options,
      dateParser: (s) -> Date.parse s
      dateRegex: null
      relaxedWhitespace: true
      requireCompletionDate: false
      ignorePriorityCase: true
      heirarchical: false
      commentRegex: /^\s*#.*$/
      projectRegex: /(?:\s+|^)\+(\S+)/g
      contextRegex: /(?:\s+|^)@(\S+)/g
      # collection of functions that parse the task text and return key:value objects
      extensions: [
        (text) ->
          metadata = {}
          metadataRegex = /(?:\s+|^)(\S+):(\S+)/g
          while match = metadataRegex.exec text
            metadata[match[1].toLowerCase()] = match[2]
          metadata
      ]