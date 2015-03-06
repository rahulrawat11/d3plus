arraySort  = require "../../../../../array/sort.coffee"
buffer     = require "./buffer.coffee"
buckets    = require "../../../../../util/buckets.coffee"
fetchData  = require "../../../../../core/fetch/data.js"
fetchValue = require "../../../../../core/fetch/value.coffee"
print      = require "../../../../../core/console/print.coffee"
uniques    = require "../../../../../util/uniques.coffee"

module.exports = (vars, opts) ->

  changed           = dataChange vars
  vars.axes.dataset = getData vars if changed or !vars.axes.dataset
  vars.axes.scale   = if opts.buffer and opts.buffer isnt true then sizeScale vars, opts.buffer else false

  for axis in ["x","y"]

    oppAxis  = if axis is "x" then "y" else "x"
    reorder  = vars.order.changed or vars.order.sort.changed or
               (vars.order.value is true and vars[oppAxis].changed)

    if !("values" of vars[axis].ticks) or changed or reorder

      print.time "calculating "+axis+" axis" if vars.dev.value

      # reset ticks
      vars[axis].reset        = true
      vars[axis].ticks.values = false

      # calculate ticks if the axis is discrete and not the time variable
      if axis is vars.axes.discrete and vars[axis].value isnt vars.time.value
        vars[axis].ticks.values = uniques vars.axes.dataset, vars[axis].value, fetchValue, vars

      # calculate range
      zero  = if [true,axis].indexOf(opts.zero) > 0 then true else false
      range = axisRange vars, axis, zero

      # flip range if Y axis
      range = range.reverse() if axis is "y"

      # calculate scale
      vars[axis].scale.viz = getScale vars, axis, range

      # Add buffer to scale if it needs it
      buffer vars, axis, opts.buffer if opts.buffer and axis isnt vars.axes.discrete

      # store axis domain
      vars[axis].domain.viz = range

      print.timeEnd "calculating "+axis+" axis" if vars.dev.value

  # Mirror axes, if applicable
  if vars.axes.mirror.value
    domains = vars.y.domain.viz.concat(vars.x.domain.viz)
    vars.x.domain.viz = d3.extent(domains)
    vars.y.domain.viz = d3.extent(domains).reverse()

  return

dataChange = (vars) ->

  changed = vars.time.fixed.value and
            (vars.time.solo.changed or vars.time.mute.changed)
  changed = vars.id.solo.changed or vars.id.mute.changed unless changed
  return changed if changed

  check = ["data", "time", "id", "depth", "type", "x", "y"]
  for k in check
    if vars[k].changed
      changed = true
      break

  subs = ["mute", "range", "scale", "solo", "stacked"]
  for axis in ["x", "y"]
    for sub in subs
      if vars[axis][sub].changed
        changed = true
        break

  changed

getData = (vars) ->
  if vars.time.fixed.value
    vars.data.viz
  else
    depths  = d3.range(0,vars.id.nesting.length)
    d3.merge [fetchData(vars,"all",d) for d in depths]

axisRange = (vars, axis, zero, buffer) ->

  oppAxis = if axis is "x" then "y" else "x"

  if vars[axis].range.value and vars[axis].range.value.length is 2
    vars[axis].range.value.slice()

  else if vars[axis].scale.value is "share"
    vars[axis].ticks.values = d3.range 0, 1.1, 0.1
    [0,1]

  else if vars[axis].stacked.value
    splitData = []
    for d in vars.axes.dataset
      if d.values
        splitData = splitData.concat d.values
      else
        splitData.push d
    axisSums = d3.nest()
      .key (d) -> fetchValue vars, d, vars[oppAxis].value
      .rollup (leaves) ->
        positives = d3.sum leaves, (d) ->
          val = fetchValue vars, d, vars[axis].value
          if val > 0 then val else 0
        negatives = d3.sum leaves, (d) ->
          val = fetchValue vars, d, vars[axis].value
          if val < 0 then val else 0
        [negatives,positives]
      .entries splitData
    values = d3.merge axisSums.map (d) -> d.values
    d3.extent values

  else if vars[axis].value is vars.time.value and vars[axis].ticks.values
    d3.extent vars[axis].ticks.values

  else
    values = []
    for d in vars.axes.dataset
      val = fetchValue vars, d, vars[axis].value
      if val instanceof Array
        values = values.concat val
      else
        values.push val
    if typeof values[0] is "string"
      if vars.order.value is true
        sortKey = vars[oppAxis].value
      else
        sortKey = vars.order.value
      if sortKey
        sort = vars.order.sort.value
        agg = vars.order.agg.value or vars.aggs.value[sortKey] or "max"
        aggType = typeof agg
        counts = values.reduce (obj, val) ->
          obj[val] = []
          obj
        , {}
        for d in vars.axes.dataset
          if d.values
            for v in d.values
              group = fetchValue vars, v, vars[axis].value
              counts[group].push fetchValue vars, v, sortKey
          else
            group = fetchValue vars, d, vars[axis].value
            counts[group].push fetchValue vars, d, sortKey
        for k, v of counts
          if aggType is "string"
            counts[k] = d3[agg] v
          else if aggType is "function"
            counts[k] = agg v, sortKey
        counts = arraySort d3.entries(counts), "value", sort
        counts = counts.reduce (arr, v) ->
          arr.push v.key
          arr
        , []
        counts
      else
        uniques values
    else
      values.sort (a, b) -> a - b
      if vars[axis].scale.value is "log"
        values[0] = 1 if values[0] is 0
        values[values.length-1] = -1 if values[values.length-1] is 0
      if zero
        allPositive = values.every (v) -> v > 0
        allNegative = values.every (v) -> v < 0
        if allPositive or allNegative
          min = if allPositive then 1 else -1
          values.push if vars[axis].scale.value is "log" then min else 0
      d3.extent values

getScale = (vars, axis, range) ->

  rangeMax  = if axis is "x" then vars.width.viz else vars.height.viz
  scaleType = vars[axis].scale.value
  scaleType = "linear" if ["discrete","share"].indexOf(scaleType) >= 0

  if typeof range[0] is "string"
    scaleType = "ordinal"
    rangeArray = buckets [0, rangeMax], range.length
  else
    rangeArray = [0, rangeMax]

  d3.scale[scaleType]()
    .domain(range).range(rangeArray)

sizeScale = (vars, value) ->

  value = "size" if value is true
  value = vars[value].value if value of vars

  min = vars.size.scale.min.value
  min = min vars if typeof min is "function"
  max = vars.size.scale.max.value
  max = max vars if typeof max is "function"

  if value is false
    vars.size.scale.value.rangeRound [max,max]
  else if typeof value is "number"
    vars.size.scale.value.rangeRound [value,value]
  else if value

    print.time "calculating buffer scale" if vars.dev.value

    domain = d3.extent vars.axes.dataset, (d) ->
      val = fetchValue vars, d, value
      if !val then 0 else val

    min = max if domain[0] is domain[1]

    print.timeEnd "calculating buffer scale" if vars.dev.value

    vars.size.scale.value
      .domain domain
      .rangeRound [min,max]
