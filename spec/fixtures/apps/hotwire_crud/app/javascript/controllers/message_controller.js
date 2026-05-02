import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]
  static values = { editable: Boolean }

  connect() {}

  edit() {}
}
