# frozen_string_literal: true

ActiveRecord::Schema[8.1].define(version: 3) do
  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "posts", force: :cascade do |t|
    t.string "title", null: false
    t.text "body"
    t.boolean "published", default: false, null: false
    t.references "user", null: false, foreign_key: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "comments", force: :cascade do |t|
    t.text "body", null: false
    t.references "post", null: false, foreign_key: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
