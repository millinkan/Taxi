# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin "channels/consumer"
# Maps for live tracking (Leaflet 1.9.4, vendored: no third-party script on
# customer pages); loaded only on pages that show one.
pin "leaflet", preload: false
