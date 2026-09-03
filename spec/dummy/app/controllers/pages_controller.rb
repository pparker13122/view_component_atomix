# frozen_string_literal: true

class PagesController < ApplicationController
  def index
    @width = params[:width]&.to_i
  end
end
