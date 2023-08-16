import './ExpenseDate.css';

function ExpenseDate(props) {
  const month = props.date.toLocaleString("en-US", { month: "long" });
  const day = props.date.toLocaleString("en-US", { day: "2-digit" });
  const year = props.date.getFullYear();

  return (
    <div className="expense-date">
      <div className ="expense-date__month">{month}</div>
      {/* expenseDate는 날짜객체이기 때문에 메소드사용해서해야함() */}
      <div className ="expense-date__year">{year}</div>
      <div claseName ="expense-date__day">{day}</div>
    </div>
  );
}

export default ExpenseDate;
