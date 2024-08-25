Provider::Engine.routes.draw do

  mount_api_endpoints("/api/v1", controller: "api/api", engine_path: "/provider") do

    model_endpoints_for("User", crud: true) do
      # --- added by default
      # get  "/users", class_action: :index
      # post  "/user", action: :update # /user?id=123
      # delete "/user", action: :delete
      # ---
      post "/users/do_something", class_action: "do_something"
    end

  end

end

