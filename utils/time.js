function addHours(numOfHours, date = new Date()) {
  return Math.floor(Date.now() / 1000) * 60 * (60 * numOfHours)
}

module.exports = {
  addHours: addHours,
}
