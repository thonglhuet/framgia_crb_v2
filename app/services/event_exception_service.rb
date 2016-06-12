class EventExceptionService

  def initialize event, params, argv = {}
    @exception_type = params[:exception_type]
    @event = event
    @event_before_update_id = @event.id
    @event_params = params
    @is_drop = argv[:is_drop].to_i rescue 0
    @start_time_before_drag = argv[:start_time_before_drag]
    @finish_time_before_drag = argv[:finish_time_before_drag]
  end

  def update_event_exception
    if @is_drop == 0
      case @event_params[:exception_type]
      when ""
        @event.update_attributes @event_params
        @event_after_update = @event
      when "edit_all"
        @event_exception_edits = if @event.event_parent.present?
          Event.exception_edits @event.event_parent.id
        else
          Event.exception_edits @event.id
        end

        initial_value @event_params[:start_date], @event_params[:finish_date], @event

        @event_after_update = @event

        (@event_exception_edits + [@event]).uniq.each do |event|
          update_attributes_event event
        end
      when "edit_only"
        save_this_event_exception @event
      when "edit_all_follow"
        initial_value @event_params[:start_date], @event_params[:finish_date], @event
        save_this_event_exception @event
        if event = event_exception_pre_nearest
          event.update_attributes end_repeat:
            DateTime.parse(@event_params[:start_date])
        else
          @event.update_attributes end_repeat:
            DateTime.parse(@event_params[:start_date])
        end
        event_after_exceptions = @event.event_exceptions.
          all_event_after_date @event_params[:start_date].to_datetime
        event_after_exceptions.each do |event|
          update_attributes_event event
        end
        event_allfollow_exceptions = @event.event_exceptions.
          event_follow_after_date @event_params[:start_date].to_datetime
        event_allfollow_exceptions.destroy_all
      end
    else
      create_event_when_drop

      if @event.event_parent.present?
        event_exception.update_attributes exception_type: 0
      else
        create_event_with_exception_delete_only
      end
    end

    if @event_after_update.present?
      SendEmailAfterEventUpdateWorker.perform_async(@event_before_update_id,
        @event_after_update.id,
        @start_time_before_drag,
        @finish_time_before_drag)
    end
  end

  private
  def initial_value start_date, finish_date, event
    @pre_start_date = event.start_date
    @pre_finish_date = event.finish_date
    @start_date = DateTime.parse(start_date)
    @finish_date = DateTime.parse(finish_date)

    @hour_start = @start_date.strftime("%H").to_i
    @minute_start = @start_date.strftime("%M").to_i
    @second_start = @start_date.strftime("%S").to_i
    @hour_end = @finish_date.strftime("%H").to_i
    @minute_end = @finish_date.strftime("%M").to_i
    @second_end = @finish_date.strftime("%S").to_i
  end

  def update_attributes_event event
    event.update_attributes(
      title: @event_params[:title],
      start_date: (event.start_date.change(
      {hour: @hour_start, min: @minute_start, sec: @second_start})),
      finish_date: (event.finish_date.change(
      {hour: @hour_end, min: @minute_end, sec: @second_end})))
  end

  def save_this_event_exception event
    if event.event_parent.present?
      event.update_attributes @event_params
      @event_after_update = event
    else
      @event_params[:parent_id] = @event.id
      @event_params[:id] = nil
      @event_after_update = @event.dup
      @event_after_update.update_attributes @event_params.permit!
    end
  end

  def event_exception_pre_nearest
    if @event.event_parent.present?
      @event.event_parent.event_exceptions
        .event_pre_nearest(@event_params[:start_date])
        .order(start_date: :desc).first
    end
  end

  def create_event_when_drop
    @event_params[:exception_type] = nil
    @event_params[:exception_time] = nil
    @event_params[:start_repeat] = @event_params[:start_date]
    @event_params[:end_repeat] = @event_params[:finish_date]
    @event_after_update = @event.dup
    @event_after_update.update_attributes @event_params.permit!
  end

  def create_event_with_exception_delete_only
    @event_params[:parent_id] = @event.id
    @event_params[:exception_type] = 0
    @event_params[:start_date] = @start_time_before_drag.to_datetime
    @event_params[:finish_date] = @finish_time_before_drag.to_datetime
    @event_params[:exception_time] = @start_time_before_drag.to_datetime
    @event.dup.update_attributes @event_params.permit!
  end
end