ActiveRecord::Schema.define(version: 2026_04_04_000000) do
  create_table "users" do |t|
    t.string "email"
    t.string "name"
    t.integer "role"
    t.timestamps
  end

  create_table "posts" do |t|
    t.string "title"
    t.text "body"
    t.references "user"
    t.timestamps
  end

  create_table "categories" do |t|
    t.string "name"
    t.timestamps
  end

  create_table "categorizations" do |t|
    t.integer "post_id"
    t.integer "category_id"
    t.timestamps
  end

  create_table "groups" do |t|
    t.string "name"
    t.timestamps
  end

  create_table "memberships" do |t|
    t.integer "user_id"
    t.integer "group_id"
    t.string "role"
    t.timestamps
  end
end
