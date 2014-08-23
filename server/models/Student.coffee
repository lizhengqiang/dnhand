mongoose = require 'mongoose'

StudentSchema = new mongoose.Schema
  stuid: { type: String, unique: true }
  pswd: { type: String, default: ""}
  name: String
  sex: String
  native: String
  class: String
  major: String
  year: String
  is_pswd_invalid: Boolean
  update_time: Date

module.exports = StudentSchema
