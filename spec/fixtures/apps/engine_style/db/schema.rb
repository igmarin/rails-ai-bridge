ActiveRecord::Schema[8.0].define(version: 2026_04_30_150000) do
  create_table "customers", force: :cascade do |t|
    t.string "email", null: false
    t.string "name", null: false
    t.string "external_reference"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_customers_on_email", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "customer_id", null: false
    t.string "plan", null: false
    t.string "status", null: false
    t.datetime "renews_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_subscriptions_on_customer_id"
  end

  create_table "invoices", force: :cascade do |t|
    t.integer "subscription_id", null: false
    t.string "number", null: false
    t.decimal "total", precision: 12, scale: 2, null: false
    t.string "status", null: false
    t.datetime "issued_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id"], name: "index_invoices_on_subscription_id"
  end
end
