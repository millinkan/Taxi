// One WebSocket per page, opened on first use (most pages never need it).
import { createConsumer } from "@rails/actioncable"

let consumer

export default function getConsumer() {
  consumer ||= createConsumer()
  return consumer
}
