try {
  require("i_dont_exist");
} catch (err) {
  module.exports = "s'all good";
}
