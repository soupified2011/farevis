
d3 = require 'd3'
moment = require 'moment'

class Flight
  # Represent an itinerary for one flight
  constructor: (@legs, @price, @startTime, @endTime, @index) ->

  superior: (otherFlight) ->
    # return true iff this flight is superior to otherFlight
    
    # is otherFlight superior to this flight?
    if otherFlight.startTime > @startTime
      return false
    if otherFlight.endTime < @endTime
      return false
    if otherFlight.price < @price
      return false

    # Is this flight superior to otherFlight?
    if otherFlight.startTime < @startTime
      return true
    if otherFlight.endTime > @endTime
      return true
    if otherFlight.price > @price
      return true

    # Arbitrary Tiebreaker
    if otherFlight.index <= @index
      return false
    return true

class Leg
  # Represent a leg of a flight (connections are considered legs, usually
  # with the same origin and destination but occasionally different airports
  # within the same city)
  constructor: (@origin, @destination, @departure, @arrival, @carrier) ->

class Airport
  # Represent an airport
  constructor: (@code, @city, @timezone, @type) ->
    @group = [this]

  pairWith: (airport) ->
    if airport not in @group
      @group = @group.concat(airport.group)
      for member in @group
        member.group = @group

  setTz: (@tz) ->
    @city.tz = @tz

  setMinHops: (hops) ->
    if (not @hops?) or hops < @hops
      @hops = hops

  setMinDuration: (duration) ->
    if (not @duration?) or duration < @duration
      @duration = duration

  @compare: (a, b) =>
    if a in b.group
      @directCompare(a, b)
    else
      minA = a.group.sort(Airport.directCompare)[0]
      minB = b.group.sort(Airport.directCompare)[0]
      @directCompare(minA, minB)

  @directCompare: (a, b) ->
    # Compare two airports to determine an order.
    # Rules for comparison are:
    #   - origin airports are always first
    #   - destination airports are always last
    # For connecting airports,
    #   - airports with a shorter minimum duration are first
    #   - if duration is the same, airports with a lower
    #     minimum number of hops (from any origin airport)  are 
    #     first
    if a.type == 'origin' or b.type == 'destination'
      return -1
    else if a.type == 'destination' or b.type == 'origin'
      return 1

    else if a.duration < b.duration
      return -1
    else if a.duration > b.duration
      return 1

    else if a.hops < b.hops
      return -1
    else if a.hops > b.hops
      return 1

    else
      return 0

class City
  # Represent a city
  constructor: (@code, @name) ->

class Carrier
  # Represent an airline
  constructor: (@code, @name, @color) ->

class FlightVisualization
  # This class is the workhorse of the visualization.
  # Gathers the data and creates the SVG.

  constructor: (@ita) ->

  createSVG: ->
    container = d3.select('#solutionPane td.itaRoundedPaneMain')
    container.select('*').remove()
    container.attr('style', 'height: 600px')
    @svg = container.append('svg:svg')
    @width = @svg[0][0].offsetWidth
    @height = @svg[0][0].offsetHeight
    @svg.append('rect')
        .attr('width', @width)
        .attr('height', @height)
        .style('fill', 'white')

  prepareScales: ->
    @airportScale = d3.scale.ordinal()
    @airportScale.domain(@airportsList)
    @airportScale.rangeBands([30, @height])

    @dateScale = d3.time.scale()
    @dateScale.domain([@minDeparture, @maxArrival])
    @dateScale.range([40, @width - 20])

    @priceScale = d3.scale.linear()
    @priceScale.domain([@minPrice, @maxPrice])
    @priceScale.range(['#00ff00', '#ff0000'])
    @priceScale.interpolate = d3.interpolateHsl

    @hourScale = d3.scale.linear()
    @hourScale.domain([0, 12, 23])
    @hourScale.range(['#0000dd', '#dddd00', '#0000dd'])
    @priceScale.interpolate = d3.interpolateHsl

  drawYAxis: ->
    @svg.selectAll('text.yAxis')
      .data(@airportsList)
      .enter()
        .append('text')
        .attr('x', 10)
        .attr('y', @airportScale)
        .style('dominant-baseline', 'middle')
        .style('font-weight', 'bold')
        .text((airport) -> airport)

  drawTimes: ->
    airportScale = @airportScale
    dateScale = @dateScale
    airports = @airports
    hourScale = @hourScale
    @svg.selectAll('g.timeGroup')
      .data(@airportsList)
      .enter()
      .append('g')
      .each (airportCode) ->
        airport = airports[airportCode]
        g = d3.select(this)
        g.attr('transform', "translate(0, #{airportScale(airportCode)})")

        g.selectAll('circle.y')
          .data(dateScale.ticks(60))
          .enter()
            .append('circle')
            .attr('cx', dateScale)
            .attr('r', 2)
            .style('opacity', 0.3)
            .attr 'fill', (time) ->
              hourScale(moment.utc(time).clone().subtract('minutes', airport.tz).hours())

        g.selectAll('circle.x')
          .data(dateScale.ticks(20))
          .enter()
            .append('circle')
            .attr('cx', dateScale)
            .attr('r', 2)
            .attr 'fill', (time) ->
              hourScale(moment.utc(time).clone().subtract('minutes', airport.tz).hours())

        g
          .selectAll('text')
          .data(dateScale.ticks(20))
          .enter()
            .append('text')
            .attr('x', dateScale)
            .attr('y', -10)
            .attr('text-anchor', 'middle')
            .attr('font-size', '8px')
            .style('dominant-baseline', 'middle')
            .text((time) -> moment.utc(time).clone().subtract('minutes', airport.tz).format('ha'))
            .attr 'fill', (time) ->
              hourScale(moment.utc(time).clone().subtract('minutes', airport.tz).hours())


  draw: ->
    @get_data()
    console.log this
    window.flightVisualization = this
    @createSVG()
    @prepareScales()
    @drawYAxis()
    @drawTimes()

    legPath = (leg) =>
      x1 = @dateScale(leg.departure)
      y1 = @airportScale(leg.origin.code)
      x2 = @dateScale(leg.arrival)
      y2 = @airportScale(leg.destination.code)
      dip = (x2 - x1) * .6
      "M #{x1},#{y1} C #{x1 + dip},#{y1} #{x2 - dip},#{y2} #{x2},#{y2}"

    priceScale = @priceScale
    f = @svg.selectAll('g.flight')
        .data(@flights)
        .enter()
          .append('g')
          .each (flight) ->
            flightPath = d3.select(this)
                          .selectAll('path')
                          .data((flight) -> flight.legs)
                          .enter()

            flightPath
                .append('path')
                .style('stroke', 'white')
                .style('stroke-width', '7')
                .style('stroke-linecap', 'square')
                .style('fill', 'none')
                .style('opacity', '.8')
                .attr('d', legPath)

            flightPath
                .append('path')
                .style('stroke', (leg) -> leg.carrier.color)
                .style('stroke-width', '3')
                .style('stroke-linecap', 'square')
                .style('fill', 'none')
                .attr('d', legPath)

  get_data: ->
    itaData = @ita.flightsPage.flightsPanel.flightList
    carrierToColorMap = @ita.flightsPage.matrix.stopCarrierMatrix.carrierToColorMap
    isoOffsetInMinutes = @ita.isoOffsetInMinutes

    @cities = {}
    @airports = {}
    @flights = []
    @carriers = {}

    @carriers.CONNECTION = new Carrier('CONNECTION', 'Connection', '#888')
    # Flight time range
    @maxArrival = moment.utc(itaData.maxArrival)
    @minDeparture = moment.utc(itaData.minDeparture)

    # Load City data
    for code, itaCity of itaData.data.cities
      city = new City(code, itaCity.name)
      @cities[code] = city

    # Load Airport data
    originCodes = itaData.originCodes
    destinationCodes = itaData.destinationCodes
    for code, itaAirport of itaData.data.airports
      if code in originCodes
        type = 'origin'
      else if code in destinationCodes
        type = 'destination'
      else
        type = 'connection'
      airport = new Airport(code, @cities[itaAirport.city],
        itaAirport.name, type)
      @airports[code] = airport

    # Load Carrier Data
    for code, itaCarrier of itaData.data.carriers
      carrier = new Carrier(code, itaCarrier.shortName,
        carrierToColorMap[code])
      @carriers[code] = carrier

    # Load Flight Data
    for solution, index in itaData.summary.solutions
      legs = []
      price = parseFloat(solution.itinerary.pricings[0].displayPrice.substring(3))
      if not @minPrice? or @minPrice > price
        @minPrice = price
      if not @maxPrice? or @maxPrice < price
        @maxPrice = price
      itaLegs = solution.itinerary.slices[0].legs

      firstLeg = itaLegs[0]
      lastLeg = itaLegs[itaLegs.length - 1]

      # Flight duration
      startTime = moment.utc(firstLeg.departure)
      endTime = moment.utc(lastLeg.arrival)

      lastLeg = null
      duration = 0
      for itaLeg, legIndex in itaLegs
        if lastLeg?
          leg = new Leg(@airports[lastLeg.destination],
                        @airports[itaLeg.origin],
                        moment.utc(lastLeg.arrival),
                        moment.utc(itaLeg.departure),
                        @carriers.CONNECTION)
          legs.push(leg)

          if lastLeg.destination != itaLeg.origin
            @airports[lastLeg.destination].pairWith(@airports[itaLeg.origin])

        airportOrigin = @airports[itaLeg.origin]
        airportDestination = @airports[itaLeg.destination]

        # Set time zones
        airportOrigin.setTz(isoOffsetInMinutes(itaLeg.departure))
        airportDestination.setTz(isoOffsetInMinutes(itaLeg.arrival))

        # Update hops table
        airportOrigin.setMinHops(legIndex)
        airportDestination.setMinHops(legIndex + 1)

        # Update duration
        airportOrigin.setMinDuration(duration)
        duration = duration + itaLeg.duration
        airportDestination.setMinDuration(duration)

        # Save leg
        leg = new Leg(airportOrigin,
                      airportDestination,
                      moment.utc(itaLeg.departure),
                      moment.utc(itaLeg.arrival),
                      @carriers[itaLeg.carrier])
        legs.push(leg)
        lastLeg = itaLeg

      flight = new Flight(legs, price, startTime, endTime, index)
      @flights.push(flight)

    # Get rid of duplicate and inferior flights
    trimmed_flights = []
    for flight1 in @flights
      trim = false
      for flight2 in @flights
        if flight2.superior(flight1)
          trim = true
          break
      if not trim
        trimmed_flights.push(flight1)
    @flights = trimmed_flights

    # Trim airports
    valid_airports = {}
    for flight in @flights
      for leg in flight.legs
        valid_airports[leg.origin.code] = leg.origin
        valid_airports[leg.destination.code] = leg.destination

    # Create a sorted list of airports
    @airportsList = (airport for i, airport of valid_airports).sort(Airport.compare)
    @airportsList = (airport.code for airport in @airportsList)

main = ->
  vis = new FlightVisualization(ita)
  vis.draw()

main()

