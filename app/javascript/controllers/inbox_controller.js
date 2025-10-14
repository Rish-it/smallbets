import { Controller } from "@hotwired/stimulus"
import { nextEventLoopTick } from "helpers/timing_helpers"
import MessageFormatter, { ThreadStyle } from "models/message_formatter"
import MessagePaginator from "models/message_paginator"

export default class extends Controller {
  static targets = [ "messages" ]
  static classes = [ "firstOfDay", "me", "threaded", "mentioned", "formatted", "loadingUp", "loadingDown" ]
  static values = { pageUrl: String }

  #paginator
  #formatter

  initialize() {
    this.#formatter = new MessageFormatter(Current.user.id, {
      firstOfDay: this.firstOfDayClass,
      formatted: this.formattedClass,
      me: this.meClass,
      mentioned: this.mentionedClass,
      threaded: this.threadedClass,
    })
  }

  connect() {
    this.#paginator = new MessagePaginator(this.messagesTarget, this.pageUrlValue, this.#formatter, () => {}, {
      loadingUp: this.loadingUpClass,
      loadingDown: this.loadingDownClass
    })

    this.element.scrollTo({ top: this.element.scrollHeight })
    this.#paginator.monitor()
  }

  disconnect() {
    this.#paginator.disconnect()
  }

  messageTargetConnected(target) {
    this.#formatter.format(target, ThreadStyle.thread)
  }

  async beforeStreamRender(event) {
    const target = event.detail.newStream.getAttribute("target")
    const action = event.detail.newStream.getAttribute("action")
    const render = event.detail.render

    if (target === "inbox") {
      // Handle prepend (new mentions), replace (thread updates), and append actions
      if (action === "prepend" || action === "replace" || action === "append") {
        event.detail.render = async (streamElement) => {
          await render(streamElement)
          await nextEventLoopTick()

          // Re-format the new or updated message
          const formattableMessages = action === "prepend"
            ? [this.messagesTarget.firstElementChild]
            : this.messageTargets.filter(el => !el.classList.contains(this.formattedClass))

          formattableMessages.forEach(message => {
            if (message) {
              this.#formatter.format(message, ThreadStyle.thread)
            }
          })
        }
      }
    }
  }
}
