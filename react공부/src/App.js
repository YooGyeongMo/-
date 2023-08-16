import Expenses from "./components/Expenses";

function App() {
  const expenses = [
    {
      id: "e1",
      title: "Toilet Paper",
      amount: 94.12,
      date: new Date(2020, 7, 14),
    },
    {
      id: "e2",
      title: "New TV",
      amount: 799.49,
      date: new Date(2021, 2, 12),
    },
    {
      id: "e3",
      title: "Car Insurance",
      amount: 294.67,
      date: new Date(2021, 2, 28),
    },
    {
      id: "e4",
      title: "New Desk (Wooden)",
      amount: 450,
      date: new Date(2021, 5, 12),
    },
  ];

  return (
    <div>
      <h2>Let's get started!</h2>
      <Expenses items={expenses}/>
    </div> //jsx syntax다. 뒤에 변환되어 실행되기 때문이다.
    //우리는 여기서 react 개발팀이 만들어낸 개발 친화적인 코드를 여기에서 사용하고
    // 크롬의 개발자 도구의 소스탭의 static/js의 chunk main chunk파일에 들어가면 변환되어 사용자에게 제공한다는것을 알 수 있다.
  );
}

export default App;

//export한것을 index.js에서import한다.
