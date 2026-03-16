import streamlit as st
import pandas as pd
import datetime
import re

# Настройка страницы (адаптивно для ПК и смартфона)
st.set_page_config(page_title="Агропарк: Управление ФОТ", layout="wide")

st.title("🌾 Агропарк «Некрасово Поле»: Штатное расписание")

# --- 1. НАСТРОЙКИ КАЛЕНДАРЯ И ПРАЗДНИКОВ ---
# Праздничные дни РФ на май 2026
holidays_may_2026 = [1, 2, 3, 9, 10, 11]

def get_days_in_month(year, month):
    num_days = (datetime.date(year, month+1, 1) - datetime.timedelta(days=1)).day if month < 12 else 31
    days = []
    for day in range(1, num_days + 1):
        dt = datetime.date(year, month, day)
        is_weekend = dt.weekday() >= 5
        is_holiday = day in holidays_may_2026
        days.append({"day": day, "is_weekend": is_weekend, "is_holiday": is_holiday})
    return days

days_info = get_days_in_month(2026, 5)
day_cols = [str(d["day"]) for d in days_info]

# --- 2. ПАРСЕР ИНТЕРВАЛОВ (Почасовая) ---
def parse_cell(val, pay_type):
    if pd.isna(val) or str(val).strip() == "":
        return 0
    val = str(val).strip()
    
    # Если почасовая и введен интервал вида "10:00-22:30"
    if pay_type == "Почасовая" and "-" in val:
        try:
            start_str, end_str = val.split("-")
            start = datetime.datetime.strptime(start_str.strip(), "%H:%M")
            end = datetime.datetime.strptime(end_str.strip(), "%H:%M")
            if end < start: end += datetime.timedelta(days=1) # Переход через полночь
            return (end - start).total_seconds() / 3600
        except:
            return 0
    # Если введено просто число часов или "1" для смены
    try:
        return float(val)
    except:
        if val.lower() == "у": return 1 # Удаленка
        return 0

# --- 3. ИНИЦИАЛИЗАЦИЯ ДАННЫХ ---
if "staff_df" not in st.session_state:
    # Базовый каркас с примером мульти-роли (Иван официант и Иван бармен)
    initial_data = {
        "Сотрудник": ["Хорошилов А.", "Светлана", "Иван", "Иван"],
        "Роль": ["Управляющий", "Ст. повар", "Официант", "Хозяйственник"],
        "Тип оплаты": ["Оклад", "Смена", "Смена", "Почасовая"],
        "Ставка": [150000, 4000, 2500, 300]
    }
    for d in day_cols: initial_data[d] = [""] * 4
    st.session_state.staff_df = pd.DataFrame(initial_data)

# --- 4. ВКЛАДКИ ПРИЛОЖЕНИЯ ---
tab1, tab2 = st.tabs(["📅 Табель и ФОТ", "💰 Премирование (KPI)"])

with tab1:
    st.subheader("Май 2026")
    
    # Цветовая подсветка праздников (красный) и выходных (желтый)
    def color_weekends(val, col_name):
        if col_name in day_cols:
            day_dict = next((item for item in days_info if str(item["day"]) == col_name), None)
            if day_dict and day_dict["is_holiday"]: return 'background-color: #ffcccc'
            if day_dict and day_dict["is_weekend"]: return 'background-color: #fff2cc'
        return ''

    # Редактируемая таблица (мобильно-адаптивная)
    st.markdown("**Инструкция:** Для оклада/смен ставьте `1`. Для почасовой вводите `10` или `10:00-22:30`.")
    edited_df = st.data_editor(
        st.session_state.staff_df,
        num_rows="dynamic",
        use_container_width=True,
        column_config={
            "Тип оплаты": st.column_config.SelectboxColumn(options=["Оклад", "Смена", "Почасовая"], required=True),
            "Ставка": st.column_config.NumberColumn(required=True)
        }
    )
    st.session_state.staff_df = edited_df
    
    # Расчет ФОТ
    calculated_data = []
    total_base_fot = 0
    
    for index, row in edited_df.iterrows():
        pay_type = row["Тип оплаты"]
        rate = float(row["Ставка"]) if pd.notna(row["Ставка"]) else 0
        
        # Подсчет отработанного (смен или часов)
        worked_units = sum([parse_cell(row[d], pay_type) for d in day_cols])
        
        if pay_type == "Оклад":
            salary = rate
        else:
            salary = worked_units * rate
            
        calculated_data.append({"Сотрудник": row["Сотрудник"], "Роль": row["Роль"], "Отработано": worked_units, "Базовый ФОТ": salary})
        total_base_fot += salary

with tab2:
    st.subheader("Распределение бонусного пула и KPI")
    
    # Инициализация колонок для премий
    kpi_df = pd.DataFrame(calculated_data)
    if "Фикс. премия" not in kpi_df: kpi_df["Фикс. премия"] = 0.0
    if "% от продаж" not in kpi_df: kpi_df["% от продаж"] = 0.0
    if "Доля пула" not in kpi_df: kpi_df["Доля пула"] = 0.0
    
    col1, col2 = st.columns(2)
    with col1:
        st.info("Установите общий бонусный пул (например, 2% от B2B выручки). Он распределится пропорционально отработанным сменам/часам.")
        bonus_pool = st.number_input("Общий бонусный пул (руб.):", min_value=0, value=50000, step=5000)
    
    # Автоматическое распределение пула
    total_worked_units = kpi_df[kpi_df["Роль"] != "Управляющий"]["Отработано"].sum() # Управленца обычно не вносят в линейный пул
    
    if total_worked_units > 0:
        kpi_df["Доля пула"] = kpi_df.apply(lambda x: (x["Отработано"] / total_worked_units * bonus_pool) if x["Роль"] != "Управляющий" else 0, axis=1)

    # Редактируемая таблица премий
    edited_kpi = st.data_editor(
        kpi_df,
        disabled=["Сотрудник", "Роль", "Отработано", "Базовый ФОТ", "Доля пула"],
        use_container_width=True
    )
    
    # Сводка
    edited_kpi["ИТОГО К ВЫПЛАТЕ"] = edited_kpi["Базовый ФОТ"] + edited_kpi["Фикс. премия"] + edited_kpi["% от продаж"] + edited_kpi["Доля пула"]
    
    st.divider()
    st.metric(label="ИТОГОВЫЙ ФОТ (с премиями)", value=f"{edited_kpi['ИТОГО К ВЫПЛАТЕ'].sum():,.2f} ₽")
    st.dataframe(edited_kpi[["Сотрудник", "Роль", "Базовый ФОТ", "ИТОГО К ВЫПЛАТЕ"]], use_container_width=True)
