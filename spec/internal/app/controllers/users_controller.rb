# frozen_string_literal: true

# Controller for managing users in the test application
# :reek:InstanceVariableAssumption
class UsersController < ApplicationController
  before_action :set_user, only: %i[show edit update destroy]

  def index
    @users = User.all
  end

  def show
  end

  def new
    @user = User.new
  end

  def create
    @user = User.new(user_params)
    respond_to_formats(@user.save)
  end

  def edit
  end

  def update
    @user.update(user_params)
    redirect_to @user
  end

  def destroy
    @user.destroy
    redirect_to users_path
  end

  private

  def respond_to_formats(saved)
    respond_to do |format|
      handle_save_response(format, saved)
    end
  end

  # :reek:ControlParameter :reek:DuplicateMethodCall :reek:InstanceVariableAssumption :reek:TooManyStatements
  def handle_save_response(format, saved)
    if saved
      format.html { redirect_to @user }
      format.json { render json: @user, status: :created }
    else
      format.html { render :new }
      format.json { render json: @user.errors, status: :unprocessable_entity }
    end
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:name, :email)
  end
end
